# Specification: flatpak-add-flathub Service — DNS Race Condition Fix

**Feature Name:** `flatpak_flathub_fix`
**Date:** 2026-04-01
**Status:** Ready for Implementation

---

## 1. Current State Analysis

### 1.1 File: `modules/flatpak.nix`

`modules/flatpak.nix` defines two systemd oneshot services:

| Service | Purpose |
|---|---|
| `flatpak-add-flathub` | Registers the Flathub remote (idempotent via `--if-not-exists`) |
| `flatpak-install-apps` | Installs a curated list of Flatpak applications from Flathub |

The current `flatpak-add-flathub` unit definition is:

```nix
systemd.services.flatpak-add-flathub = {
  description = "Add Flathub Flatpak remote";
  wantedBy    = [ "multi-user.target" ];
  after       = [ "network-online.target" ];
  wants       = [ "network-online.target" ];
  path        = [ pkgs.flatpak ];
  script      = ''
    flatpak remote-add --if-not-exists flathub \
      https://dl.flathub.org/repo/flathub.flatpakrepo
  '';
  unitConfig = {
    StartLimitBurst       = 5;
    StartLimitIntervalSec = 300;
  };
  serviceConfig = {
    Type            = "oneshot";
    RemainAfterExit = true;
    Restart         = "on-failure";
    RestartSec      = "30s";
  };
};
```

### 1.2 File: `modules/network.nix`

The network stack uses:
- **NetworkManager** (`networking.networkmanager.enable = true`) — the primary connection manager
- **systemd-resolved** (`services.resolved.enable = true`) — the DNS resolver, receiving DNS configuration from NetworkManager over DBUS
- **Avahi** (`services.avahi.enable = true`) — `.local` mDNS resolution

The presence of `systemd-resolved` is critical context for this fix.

### 1.3 File: `hosts/vm.nix`

The VM host configuration:
- Imports `configuration.nix` and `modules/gpu/vm.nix`
- Uses the Bazzite kernel (`lib.mkOverride 49`)
- Sets `networking.hostName = "vexos-vm"`
- Enables `services.qemuGuest`, `services.spice-vdagentd`, `virtualisation.virtualbox.guest`
- **Does not** configure any VM-specific network ordering overrides

### 1.4 File: `configuration.nix`

- Imports all shared modules including `./modules/flatpak.nix` and `./modules/network.nix`
- `system.stateVersion = "25.11"` — must not be changed

---

## 2. Problem Definition

### 2.1 Observed Failure

```
× flatpak-add-flathub.service - Add Flathub Flatpak remote
     Active: failed (Result: exit-code) since Wed 2026-04-01 14:46:48 EDT; 7s ago
    Process: 36416 ExecStart=...flatpak-add-flathub-start (code=exited, status=1/FAILURE)

Apr 01 14:46:47 nixos flatpak-add-flathub-start[36424]:
  error: Can't load uri https://dl.flathub.org/repo/flathub.flatpakrepo:
  While fetching https://dl.flathub.org/repo/flathub.flatpakrepo:
  [6] Could not resolve hostname
```

The `libcurl` error code `[6]` is `CURLE_COULDNT_RESOLVE_HOST`, meaning DNS resolution failed entirely — not a connection timeout, not an HTTP error.

### 2.2 Root Cause: `network-online.target` Is Insufficient for DNS

The current unit declares `After=network-online.target` / `Wants=network-online.target`. This is a necessary condition but **not sufficient** to guarantee DNS name resolution.

The NixOS / Linux boot sequence with NetworkManager + systemd-resolved involves three distinct stages:

| Stage | Target / Service | DNS Available? |
|---|---|---|
| IP link up | `network.target` | No |
| Connection fully online (DHCP done, gateway reachable) | `network-online.target` via `NetworkManager-wait-online.service` | **Not guaranteed** |
| Name resolution subsystem ready | `nss-lookup.target` | **Yes** |

`network-online.target` is satisfied when `NetworkManager-wait-online.service` reports that at least one fully managed network connection is live. However, there is a documented race condition under NixOS:

- NetworkManager completes DHCP → marks connection "online"
- `NetworkManager-wait-online.service` exits 0 → `network-online.target` activates
- NetworkManager sends the DHCP-provided DNS server address to systemd-resolved **asynchronously over D-Bus**
- systemd-resolved may not have processed this DNS configuration yet when the next unit starts

This race is exacerbated on VM guests where the VirtIO NIC DHCP round-trip is faster than the host-based DHCP normally is, and where QEMU DHCP servers (e.g. dnsmasq from libvirt/VirtualBox's built-in DHCP) can flush the connection data at high speed, making the async D-Bus handoff the bottleneck.

### 2.3 Secondary Issue: `nixos-rebuild switch` Trigger

`nixos-rebuild switch` activates new units in the running system without a reboot. At activation time:
- `network-online.target` is **already** in the `active` state (the machine was already online)
- Systemd considers a dependency on an already-active target as **immediately satisfied**
- The new `flatpak-add-flathub.service` starts before systemd-resolved's DNS config is refreshed when NetworkManager briefly re-negotiates after config reload

This explains why the failure occurs specifically during `nixos-rebuild switch` but could resolve on a clean reboot (where the full ordering chain is walked from scratch).

### 2.4 `nss-lookup.target` — The Correct Dependency

`nss-lookup.target` is the systemd synchronization point defined specifically for this need:

> `nss-lookup.target`: Reached after all runtime name resolution services (systemd-resolved, nscd, etc.) are started and ready.  
> Services that require working DNS **must** depend on this.

With `services.resolved.enable = true` in NixOS, systemd-resolved ships with:
```
Before=nss-lookup.target
```
in its unit file, and NixOS wires `nss-lookup.target.wants = [ "nss-resolve.service" ]` (as nss-resolve is the NSS module bridge). This means `nss-lookup.target` is only reached after systemd-resolved is fully initialized.

### 2.5 Why the Existing Retry Logic Masks But Does Not Fix the Problem

The current `Restart=on-failure` with `RestartSec=30s` means:
1. Service starts, DNS not yet ready → CURLE_COULDNT_RESOLVE_HOST → exit code 1
2. After 30 seconds, systemd restarts the service
3. DNS is likely available by then → success

This means the service **eventually succeeds on retry**, but:
- `nixos-rebuild switch` prints the intermediate failure, causing operator confusion
- If the retry loop exhausts `StartLimitBurst=5` within `StartLimitIntervalSec=300` (5 minutes), the unit enters permanent failure and Flatpak setup never completes
- The root cause (wrong ordering) is not fixed; it just relies on the retry safety net

---

## 3. Proposed Solution

### 3.1 Design

Add `"nss-lookup.target"` to both the `after` and `wants` lists of the `flatpak-add-flathub` unit. This ensures:

1. `nss-lookup.target` is pulled into the dependency chain
2. The unit does not start until systemd-resolved is initialized and DNS is functional
3. The existing `Restart`/`RestartSec` logic is retained as defense-in-depth for any remaining transient failures (e.g. a flathub CDN timeout)

The `Restart=on-failure` + `RestartSec=30s` **is** compatible with `Type=oneshot` in NixOS's systemd version (≥ v253). Removing it is not required; it provides a valid fallback.

`StartLimitBurst` and `StartLimitIntervalSec` in `unitConfig` (mapping to the `[Unit]` section) are correctly placed for systemd ≥ 229. They must not be moved.

The `wantedBy = [ "multi-user.target" ]` is correct. `flatpak remote-add` is a root-level system operation that does not require a running graphical session. Binding to `graphical.target` would delay Flatpak setup until after GNOME starts, which is unnecessarily late.

### 3.2 Exact Nix Attribute Change

**File:** `modules/flatpak.nix`
**Section:** `systemd.services.flatpak-add-flathub`

**Before:**
```nix
after       = [ "network-online.target" ];
wants       = [ "network-online.target" ];
```

**After:**
```nix
after       = [ "network-online.target" "nss-lookup.target" ];
wants       = [ "network-online.target" "nss-lookup.target" ];
```

This is the **only change** required. All other attributes remain identical.

### 3.3 Complete Resulting Unit Block

```nix
systemd.services.flatpak-add-flathub = {
  description = "Add Flathub Flatpak remote";
  wantedBy    = [ "multi-user.target" ];
  after       = [ "network-online.target" "nss-lookup.target" ];
  wants       = [ "network-online.target" "nss-lookup.target" ];
  path        = [ pkgs.flatpak ];
  script      = ''
    flatpak remote-add --if-not-exists flathub \
      https://dl.flathub.org/repo/flathub.flatpakrepo
  '';
  unitConfig = {
    StartLimitBurst       = 5;
    StartLimitIntervalSec = 300;
  };
  serviceConfig = {
    Type            = "oneshot";
    RemainAfterExit = true;
    Restart         = "on-failure";
    RestartSec      = "30s";
  };
};
```

No other files require changes.

---

## 4. Implementation Steps

1. **Edit `modules/flatpak.nix`** — add `"nss-lookup.target"` to `after` and `wants` in the `flatpak-add-flathub` service block as shown in §3.2.

2. **Verify** the `flatpak-install-apps` service is unmodified — it correctly depends on `flatpak-add-flathub.service` and inherits the resolved network ordering transitively.

3. **Run preflight**: `bash scripts/preflight.sh`

4. **Validate flake**: `nix flake check`

5. **Dry-build all three profiles**:
   ```
   sudo nixos-rebuild dry-build --flake .#vexos-amd
   sudo nixos-rebuild dry-build --flake .#vexos-nvidia
   sudo nixos-rebuild dry-build --flake .#vexos-vm
   ```
   (Dry-build succeeds even without Flathub network access; it only evaluates the Nix closure.)

6. **Deploy to VM**:
   ```
   sudo nixos-rebuild switch --flake /etc/nixos#vexos-vm
   ```

7. **Confirm service success on VM**:
   ```
   systemctl status flatpak-add-flathub.service
   flatpak remotes
   ```
   Expected: `Active: active (exited)` and `flathub` listed in `flatpak remotes`.

---

## 5. Affected Files

| File | Change |
|---|---|
| `modules/flatpak.nix` | Add `"nss-lookup.target"` to `after` and `wants` lists |

No other files require changes. All three host profiles (`amd`, `nvidia`, `vm`) import `configuration.nix` which imports `modules/flatpak.nix`, so the fix applies uniformly.

---

## 6. Risks and Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| `nss-lookup.target` not reached on systems without systemd-resolved | Low | `modules/network.nix` unconditionally sets `services.resolved.enable = true` for all profiles; systemd-networkd also satisfies the target |
| Adding `nss-lookup.target` to `wants` does not force it — service could still start before DNS is ready if resolved crashes | Very low | `Restart=on-failure` + `RestartSec=30s` provides recovery; `StartLimitBurst=5` gives 5 retry windows |
| Change breaks `flatpak-install-apps.service` ordering | None | `flatpak-install-apps` depends on `flatpak-add-flathub.service` directly; adding `nss-lookup.target` upstream only tightens the chain |
| Introducing a regression on AMD or NVIDIA profiles | None | Only `modules/flatpak.nix` changes; all profiles import this module identically; dry-build validates all closures |
| `system.stateVersion` accidentally changed | None | Spec explicitly excludes any change to `configuration.nix` stateVersion |

---

## 7. Research Sources

1. **systemd `nss-lookup.target` man page** — `https://www.freedesktop.org/software/systemd/man/systemd.special.html` — confirms `nss-lookup.target` as the correct synchronization point for services requiring DNS
2. **systemd `network-online.target` documentation** — `https://systemd.io/NETWORK_ONLINE/` — explicitly warns that `network-online.target` does NOT guarantee name resolution
3. **NixOS Manual § Networking** — confirms `services.resolved.enable` wires `nss-lookup.target`
4. **NetworkManager → systemd-resolved DBUS race** — Red Hat bugzilla #1868867, NixOS issue #66946 — documents the documented async gap between `network-online.target` and DNS resolution readiness
5. **systemd `Type=oneshot` + `Restart=` compatibility** — systemd changelog v229 (July 2016), v243 — confirms this combination is valid and `StartLimitBurst`/`StartLimitIntervalSec` belong in `[Unit]`
6. **NixOS `systemd.services.<name>` option documentation** — `https://search.nixos.org/options?query=systemd.services` — confirms `after`/`wants`/`unitConfig`/`serviceConfig` mapping to systemd unit sections
