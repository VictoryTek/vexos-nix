# Spec: Fix Proxmox Bridge vmbr0 Has No Working DHCP Client

**Date:** 2026-05-15
**Author:** Research & Specification Agent
**Status:** Ready for Implementation

---

## 1. Current State Analysis

### 1.1 `modules/network.nix` — global dhcpcd kill

Lines 29–30 of `network.nix`:

```nix
networking.useDHCP = lib.mkForce false;
networking.dhcpcd.enable = lib.mkForce false;
```

The inline comment correctly explains the rationale: `nixos-generate-config` emits per-interface `useDHCP = lib.mkDefault true` entries, and without this force-off dhcpcd starts alongside NetworkManager and conflicts with it, causing NM to mark interfaces as "strictly unmanaged."

The critical effect: `networking.dhcpcd.enable = lib.mkForce false` uses priority 50 (`lib.mkForce` = `lib.mkOverride 50`). No downstream module can raise this unless it uses `lib.mkOverride` with a **lower** priority number (0–49), which would be extreme and wrong.

### 1.2 `modules/server/proxmox.nix` — broken networking block

The active lines in `config = lib.mkIf cfg.enable { ... }` (lines 71–82):

```nix
# ── vmbr0 bridge ─────────────────────────────────────────────────────────
networking.bridges.vmbr0.interfaces = [ cfg.bridgeInterface ];

networking.interfaces.vmbr0.useDHCP              = lib.mkDefault true;
networking.interfaces.${cfg.bridgeInterface}.useDHCP = false;

# NetworkManager must not manage the physical NIC or the bridge
networking.networkmanager.unmanaged = [ cfg.bridgeInterface "vmbr0" ];
```

**Three independent failures combine to break networking:**

| Line | Problem |
|------|---------|
| `networking.interfaces.vmbr0.useDHCP = lib.mkDefault true` | This is a scripted-networking / dhcpcd directive. The NixOS dhcpcd module's `enableDHCP` guard is `config.networking.dhcpcd.enable && (…)`. With dhcpcd forced off in `network.nix`, this line has **zero effect** — no DHCP request is ever made. |
| `networking.interfaces.${cfg.bridgeInterface}.useDHCP = false` | Also a dhcpcd directive. Harmless since dhcpcd is already off, but misleading — implies dhcpcd is the networking backend. |
| `networking.networkmanager.unmanaged = [ cfg.bridgeInterface "vmbr0" ]` | Explicitly tells NetworkManager **not** to manage either interface. This is the correct thing to do when the physical NIC is enslaved into a kernel bridge that dhcpcd manages — but dhcpcd is off, so vmbr0 has **no client at all**. |

### 1.3 Evidence from nixpkgs dhcpcd.nix source

The nixpkgs `nixos/modules/services/networking/dhcpcd.nix` (nixos-25.05, commit `aefcb0d`) defines the `enableDHCP` gate:

```nix
enableDHCP =
  config.networking.dhcpcd.enable
  && (config.networking.useDHCP || lib.any (i: i.useDHCP == true) interfaces);
```

When `networking.dhcpcd.enable = false` (forced), `enableDHCP` short-circuits to `false` regardless of any per-interface `useDHCP` values. The dhcpcd systemd service is never written, never started, and vmbr0 never gets a DHCP lease.

### 1.4 Boot sequence on an affected host

1. System activates → `network-setup.service` runs → bridge `vmbr0` is created and `cfg.bridgeInterface` is enslaved (via `networking.bridges.vmbr0.interfaces`).
2. NetworkManager starts → reads `unmanaged-devices = enp2s0;vmbr0` from `NetworkManager.conf` → skips both.
3. dhcpcd is not running (forced off).
4. `vmbr0` comes up with no IPv4 address.
5. Proxmox web UI on port 8006 is reachable only on localhost; `nixos-rebuild switch` from another machine hangs.

### 1.5 Role scope

Only the `server` and `headless-server` roles import `./modules/server` (which includes `proxmox.nix`):

- `configuration-server.nix` — imports `./modules/server`
- `configuration-headless-server.nix` — imports `./modules/server`

The bug is latent until a user sets `vexos.server.proxmox.enable = true` and `vexos.server.proxmox.bridgeInterface`. Desktop, htpc, stateless, and vanilla roles are unaffected.

---

## 2. Problem Definition (Root Cause)

**Root cause:** `modules/server/proxmox.nix` was written for a system where dhcpcd is the active DHCP client (`networking.useDHCP = true`). The subsequent introduction of `networking.dhcpcd.enable = lib.mkForce false` in `network.nix` — which correctly kills dhcpcd to prevent NM conflicts — was not reflected in `proxmox.nix`. The bridge DHCP setup relies entirely on a backend that is unconditionally disabled.

**Secondary contributing factor:** `networking.networkmanager.unmanaged = [ cfg.bridgeInterface "vmbr0" ]` correctly prevents NM from managing the interfaces when dhcpcd is the DHCP client. With dhcpcd off and NM as the sole network daemon, this line prevents the only available DHCP client from reaching vmbr0.

---

## 3. Proposed Solution Architecture

### 3.1 Options Evaluated

#### Option A — Re-enable dhcpcd scoped to vmbr0

```nix
networking.dhcpcd.enable        = lib.mkOverride 0 true;  # beats lib.mkForce (priority 50)
networking.dhcpcd.allowInterfaces = [ "vmbr0" ];
```

**Verdict: REJECTED.**

- `lib.mkOverride 0` is the highest possible priority override — more aggressive than `lib.mkForce`. Using it to defeat an explicit architectural decision (`lib.mkForce false`) in a shared module is wrong and fragile.
- Two DHCP clients active simultaneously: NM's internal DHCP client for general interfaces + dhcpcd for vmbr0. This reintroduces exactly the conflict class that `network.nix` was designed to eliminate.
- Even with `allowInterfaces`, dhcpcd service would be running as a system daemon. Future modules that create interfaces NM doesn't manage could accidentally get dhcpcd'd.
- Violates the intent of the design documented in `network.nix`.

#### Option B — Switch vmbr0 to systemd-networkd

Configure `systemd.network.networks."10-vmbr0"` with `DHCP = "yes"`. The bridge creation continues via `networking.bridges` (scripted networking); networkd only handles L3 (DHCP) for vmbr0.

**Verdict: REJECTED.**

- Introduces a third networking backend (scripted networking for L2, networkd for L3, NM for everything else). This is unnecessary complexity.
- `systemd.network.enable = true` activates networkd system-wide; careful configuration is required to prevent networkd from managing NM-controlled interfaces.
- The NixOS `networking.useNetworkd` option would switch ALL interfaces to networkd, which breaks NM.
- Mixing `networking.bridges` (scripted) + `systemd.network.networks` is opaque to operators and adds maintenance burden.
- Inconsistent with the project's NM-first architecture.

#### Option C — Hand vmbr0 to NetworkManager via ensureProfiles keyfile ✅

Replace the scripted-networking bridge block with NM keyfile profiles:
- A **bridge master** profile: `type=bridge`, `interface-name=vmbr0`, `ipv4.method=auto`
- A **bridge slave** profile: `type=ethernet`, `interface-name=<physical NIC>`, `controller=vmbr0`, `port-type=bridge`

Remove vmbr0 and the physical NIC from `networking.networkmanager.unmanaged` so NM manages them.
Remove `networking.bridges.vmbr0.interfaces` so scripted networking does not race NM for bridge creation.
Remove the dead `networking.interfaces.*.useDHCP` lines.

**Verdict: SELECTED.**

- Consistent with the project's NM-primary architecture (`networking.networkmanager.enable = true` in `network.nix`).
- Consistent with the existing `ensureProfiles` pattern already used in `network.nix` (the `wired-fallback` and commented-out `wired-static` profiles).
- NM natively supports bridge master/slave connections via keyfile profiles (documented in NetworkManager keyfile spec; see `nm-settings-keyfile(5)`).
- No conflict with `networking.dhcpcd.enable = lib.mkForce false` — NM uses its own internal DHCP client, independent of dhcpcd.
- NM's `ensure-profiles.service` runs `after = NetworkManager.service`, `before = network-online.target`, so the bridge is active before any service that waits on `network-online.target`.
- No `lib.mkIf` guards required; the fix is unconditional within the existing `lib.mkIf cfg.enable { }` block.
- Aligns with the Module Architecture Pattern: proxmox.nix is a role-specific module (server/headless-server), and the change is scoped to that module with no conditional logic.

### 3.2 Architecture Pattern Compliance

The fix makes no changes to `network.nix` (the universal base). All changes are in `modules/server/proxmox.nix`, a role-specific module imported only by `configuration-server.nix` and `configuration-headless-server.nix`. No `lib.mkIf` guards are added. The module expresses its networking needs entirely through unconditional option assignments.

---

## 4. Exact Implementation Steps

### Step 1 — Rewrite the networking block in `modules/server/proxmox.nix`

**Remove** the following block (lines 71–82):

```nix
# ── vmbr0 bridge ─────────────────────────────────────────────────────────
# Proxmox VMs and LXC containers attach to vmbr0 for network access.
# The physical NIC is enslaved into the bridge; the bridge itself gets the
# DHCP lease. NetworkManager is told to leave both interfaces unmanaged so
# it doesn't fight the kernel bridge stack.
networking.bridges.vmbr0.interfaces = [ cfg.bridgeInterface ];

networking.interfaces.vmbr0.useDHCP              = lib.mkDefault true;
networking.interfaces.${cfg.bridgeInterface}.useDHCP = false;

# NetworkManager must not manage the physical NIC or the bridge — if it
# does it will race with the kernel bridge and drop the DHCP lease.
networking.networkmanager.unmanaged = [ cfg.bridgeInterface "vmbr0" ];
```

**Replace with** this block:

```nix
# ── vmbr0 bridge — managed by NetworkManager ────────────────────────────
# NetworkManager creates vmbr0 as a bridge, slaves the physical NIC into
# it, and obtains the DHCP lease on vmbr0 via NM's internal DHCP client.
#
# Why NM profiles (not scripted networking / dhcpcd):
#   network.nix forces networking.dhcpcd.enable = lib.mkForce false to
#   prevent dhcpcd/NM conflicts on every role.  networking.interfaces.*.useDHCP
#   is a dhcpcd directive — it is completely inert when dhcpcd is off.
#   NM is the sole DHCP client on this system; vmbr0 must be managed by NM.
#
# Why no networking.networkmanager.unmanaged entry:
#   The previous code marked both interfaces unmanaged to prevent NM from
#   racing with dhcpcd.  With NM as the only client, unmanaged is wrong —
#   it would leave vmbr0 with no IP address.
#
# Why no networking.bridges.vmbr0:
#   networking.bridges uses scripted networking (ip link) to create the
#   bridge.  Having both scripted networking and NM create the same bridge
#   races at boot.  NM creates the bridge when it activates the master
#   profile; scripted networking is not needed.
networking.networkmanager.ensureProfiles.profiles = {
  # Bridge master: NM creates vmbr0 and obtains a DHCP lease on it.
  "vmbr0-bridge" = {
    connection = {
      id             = "vmbr0 Bridge";
      type           = "bridge";
      interface-name = "vmbr0";
      autoconnect    = "true";
    };
    ipv4 = {
      method = "auto";
    };
    ipv6 = {
      method        = "auto";
      addr-gen-mode = "stable-privacy";
    };
  };

  # Bridge slave: NM enslaves the physical NIC into vmbr0.
  # The physical NIC carries no IP address; all traffic goes through the bridge.
  "vmbr0-slave" = {
    connection = {
      id             = "vmbr0 Port ${cfg.bridgeInterface}";
      type           = "ethernet";
      interface-name = cfg.bridgeInterface;
      controller     = "vmbr0";
      port-type      = "bridge";
      autoconnect    = "true";
    };
  };
};
```

### Step 2 — Verify the rest of the config block is unchanged

The following lines in `config = lib.mkIf cfg.enable { ... }` are **not modified**:

```nix
services.proxmox-ve = {
  enable    = true;
  ipAddress = cfg.ipAddress;
};

# ── Firewall ────────────────────────────────────────────────────────────
networking.firewall.allowedTCPPorts = [ 8006 8007 ];

# Allow the kernel to forward packets between the bridge and VM tap interfaces.
boot.kernel.sysctl = {
  "net.ipv4.ip_forward"          = 1;
  "net.ipv6.conf.all.forwarding" = 1;
};
```

No changes to `flake.nix`, `modules/network.nix`, `configuration-server.nix`, `configuration-headless-server.nix`, or any host file.

### Complete Resulting File

After the edit, `modules/server/proxmox.nix` should read:

```nix
# modules/server/proxmox.nix
# Proxmox VE — open-source virtualisation platform (KVM VMs + LXC containers).
# Source: https://github.com/SaumonNet/proxmox-nixos
#
# Binary cache (avoids rebuilding Proxmox packages from source):
#   nix.settings.substituters       = [ "https://cache.saumon.network/proxmox-nixos" ];
#   nix.settings.trusted-public-keys = [ "proxmox-nixos:D9RYSWpQQC/msZUWphOY2I5RLH5Dd6yQcaHIuug7dWM=" ];
#
# ⚠ Experimental — not recommended for production machines.
# ⚠ The proxmox-nixos overlay (`proxmoxOverlayModule`) and the proxmox-ve NixOS
#   module are both applied at the flake level (in `roles.server/headless-server
#   .baseModules`). The overlay makes `pkgs.proxmox-ve` available; the NixOS
#   module defines `services.proxmox-ve.*` options. Neither needs re-applying here.
#
# Impermanence note: if running on the stateless role, add /var/lib/pve-cluster
# to your persistence directories to survive reboots with the cluster config intact.
{ config, lib, ... }:
let
  cfg = config.vexos.server.proxmox;
in
{
  # Note: inputs.proxmox-nixos.nixosModules.proxmox-ve is imported at the
  # flake level (serverBase / headlessServerBase) to avoid infinite recursion
  # — using `inputs` in `imports` here triggers _module.args evaluation before
  # config is available.

  options.vexos.server.proxmox = {
    enable = lib.mkEnableOption "Proxmox VE hypervisor";

    ipAddress = lib.mkOption {
      type        = lib.types.str;
      default     = "";
      description = ''
        IP address of this host. Used by Proxmox VE for cluster communication
        and the web-UI TLS certificate. Must be set when enable = true.
      '';
    };

    bridgeInterface = lib.mkOption {
      type        = lib.types.str;
      default     = "";
      example     = "enp2s0";
      description = ''
        Name of the physical NIC to enslave into the vmbr0 bridge.
        vmbr0 is the standard Proxmox bridge — VMs and LXC containers attach
        to it for network access. Must be set when enable = true.
        Find the name with: ip link show
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.ipAddress != "";
        message   = "vexos.server.proxmox.ipAddress must be set to this host's IP address when vexos.server.proxmox.enable = true.";
      }
      {
        assertion = cfg.bridgeInterface != "";
        message   = "vexos.server.proxmox.bridgeInterface must be set to the physical NIC name (e.g. \"enp2s0\") when vexos.server.proxmox.enable = true.";
      }
    ];

    services.proxmox-ve = {
      enable    = true;
      ipAddress = cfg.ipAddress;
    };

    # ── vmbr0 bridge — managed by NetworkManager ────────────────────────────
    # NetworkManager creates vmbr0 as a bridge, slaves the physical NIC into
    # it, and obtains the DHCP lease on vmbr0 via NM's internal DHCP client.
    #
    # Why NM profiles (not scripted networking / dhcpcd):
    #   network.nix forces networking.dhcpcd.enable = lib.mkForce false to
    #   prevent dhcpcd/NM conflicts on every role.  networking.interfaces.*.useDHCP
    #   is a dhcpcd directive — it is completely inert when dhcpcd is off.
    #   NM is the sole DHCP client on this system; vmbr0 must be managed by NM.
    #
    # Why no networking.networkmanager.unmanaged entry:
    #   The previous code marked both interfaces unmanaged to prevent NM from
    #   racing with dhcpcd.  With NM as the only client, unmanaged is wrong —
    #   it would leave vmbr0 with no IP address.
    #
    # Why no networking.bridges.vmbr0:
    #   networking.bridges uses scripted networking (ip link) to create the
    #   bridge.  Having both scripted networking and NM create the same bridge
    #   races at boot.  NM creates the bridge when it activates the master
    #   profile; scripted networking is not needed.
    networking.networkmanager.ensureProfiles.profiles = {
      # Bridge master: NM creates vmbr0 and obtains a DHCP lease on it.
      "vmbr0-bridge" = {
        connection = {
          id             = "vmbr0 Bridge";
          type           = "bridge";
          interface-name = "vmbr0";
          autoconnect    = "true";
        };
        ipv4 = {
          method = "auto";
        };
        ipv6 = {
          method        = "auto";
          addr-gen-mode = "stable-privacy";
        };
      };

      # Bridge slave: NM enslaves the physical NIC into vmbr0.
      # The physical NIC carries no IP address; all traffic goes through the bridge.
      "vmbr0-slave" = {
        connection = {
          id             = "vmbr0 Port ${cfg.bridgeInterface}";
          type           = "ethernet";
          interface-name = cfg.bridgeInterface;
          controller     = "vmbr0";
          port-type      = "bridge";
          autoconnect    = "true";
        };
      };
    };

    # ── Firewall ────────────────────────────────────────────────────────────
    # 8006 = Proxmox web UI / API
    # 8007 = VNC/SPICE websocket proxy (noVNC console)
    networking.firewall.allowedTCPPorts = [ 8006 8007 ];

    # Allow the kernel to forward packets between the bridge and VM tap interfaces.
    boot.kernel.sysctl = {
      "net.ipv4.ip_forward"          = 1;
      "net.ipv6.conf.all.forwarding" = 1;
    };
  };
}
```

---

## 5. Files to Be Modified

| File | Change |
|------|--------|
| `modules/server/proxmox.nix` | Replace scripted-networking bridge block with NM `ensureProfiles` bridge + slave profiles. Remove `networking.bridges`, `networking.interfaces.*.useDHCP`, and `networking.networkmanager.unmanaged`. |

No other files require modification.

---

## 6. Risks and Mitigations

### Risk 1 — Active Proxmox deployment loses IP during `nixos-rebuild switch`

**Description:** On a live Proxmox host, switching to the new config causes:
1. The old `networking.bridges.vmbr0` scripted entry is removed.
2. The old `networking.networkmanager.unmanaged` entry is removed → NM now manages the interfaces.
3. NM activates the new profiles, creates vmbr0, and requests a DHCP lease.
4. During this transition window (seconds), vmbr0 has no IP.

**Mitigation:**
- The transition is brief (NM brings up the bridge in < 5 seconds on modern hardware).
- If connected over Tailscale or a second NIC, the rebuild can be issued safely.
- If the only path to the machine is through vmbr0, schedule the rebuild during a maintenance window and have IPMI/console access as fallback.
- DHCP will re-assign the same IP if the DHCP server uses lease persistence (standard behavior).

### Risk 2 — NM profile key collision with other server modules

**Description:** Other modules could set `networking.networkmanager.ensureProfiles.profiles."vmbr0-bridge"` or `"vmbr0-slave"`. The NixOS `attrsOf` type for `ensureProfiles.profiles` would result in a merge conflict error.

**Mitigation:**
- The profile keys `"vmbr0-bridge"` and `"vmbr0-slave"` are specific to Proxmox. No other module in `modules/server/` touches these keys.
- The `lib.mkIf cfg.enable` guard ensures they are only active when Proxmox is enabled.

### Risk 3 — `wired-fallback` profile in `network.nix` matches the physical NIC before the bridge slave profile activates

**Description:** The `wired-fallback` profile (`type=ethernet`, `autoconnect-priority=-999`) could match `cfg.bridgeInterface` during early boot before the bridge slave profile is written by `ensure-profiles.service`.

**Mitigation:**
- The bridge slave profile binds by `interface-name = cfg.bridgeInterface` (priority 0 vs wired-fallback's -999). NM selects the most specific and highest-priority matching profile.
- Even if wired-fallback activates briefly, it is immediately replaced by the bridge slave profile when `ensure-profiles.service` runs and reloads NM connections.
- The NM documentation confirms that interface-name-bound profiles override type-only profiles.

### Risk 4 — NM bridge uses a different MAC address than expected by Proxmox

**Description:** When NM creates a bridge, it may assign the physical NIC's MAC to vmbr0 (standard kernel behavior) or generate a new one. Proxmox uses `cfg.ipAddress` for cluster communication, not the MAC, so this is low risk.

**Mitigation:**
- Linux kernel bridge default: the bridge takes the MAC of the first enslaved NIC. This matches historical behavior.
- No MAC pinning is required for Proxmox DHCP use; the DHCP server assigns IP based on the MAC of vmbr0.
- If a static IP is required, the user should configure a `wired-static` style profile for vmbr0 instead of `ipv4.method = "auto"`. This is outside scope of this bug fix.

### Risk 5 — `networking.bridges.vmbr0` removal breaks `nix flake check`

**Description:** If any other module references `config.networking.bridges.vmbr0`, removing the attribute could cause evaluation failure.

**Mitigation:**
- Searching the codebase: no other module references `networking.bridges.vmbr0` or `networking.bridges` at all.
- `nix flake check` must be run as part of the review phase.

---

## 7. Verification Steps

### 7.1 Build validation (no live host required)

```bash
# Validate flake structure and evaluate all nixosConfigurations
nix flake check

# Dry-build the server and headless-server AMD variants (affected roles)
sudo nixos-rebuild dry-build --flake .#vexos-server-amd
sudo nixos-rebuild dry-build --flake .#vexos-headless-server-amd

# Dry-build the NVIDIA variants for completeness
sudo nixos-rebuild dry-build --flake .#vexos-server-nvidia
sudo nixos-rebuild dry-build --flake .#vexos-headless-server-nvidia

# Confirm non-server roles are unaffected
sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd
```

### 7.2 Runtime validation (on a live Proxmox host)

After `sudo nixos-rebuild switch --flake .#vexos-headless-server-amd` (or appropriate variant):

```bash
# 1. Confirm NM created the bridge and bridge slave profiles
nmcli connection show

# Expected output includes:
#   vmbr0 Bridge    <uuid>  bridge     vmbr0
#   vmbr0 Port enp2s0  <uuid>  ethernet   enp2s0

# 2. Confirm vmbr0 has an IPv4 address
ip addr show vmbr0

# Expected: inet <DHCP_IP>/24 brd ... scope global dynamic vmbr0

# 3. Confirm physical NIC has no IP (it's a bridge slave)
ip addr show enp2s0

# Expected: no inet line; state UP; master vmbr0

# 4. Confirm Proxmox web UI is reachable
curl -kI https://localhost:8006

# Expected: HTTP/1.1 200 OK (or 302 redirect)

# 5. Confirm dhcpcd is not running
systemctl status dhcpcd || echo "dhcpcd not active (expected)"

# 6. Confirm NM is managing vmbr0 (not unmanaged)
nmcli device status | grep vmbr0

# Expected: vmbr0  bridge  connected  vmbr0 Bridge
```

### 7.3 Preflight script

Run the project's preflight:

```bash
bash scripts/preflight.sh
```

Expected: exit code 0.

---

## 8. Research Sources

1. **nixpkgs `dhcpcd.nix` source** (nixos-25.05, commit `aefcb0d`): confirms `enableDHCP` gate — `networking.dhcpcd.enable && (useDHCP || any per-iface)`. URL: `https://github.com/NixOS/nixpkgs/blob/nixos-25.05/nixos/modules/services/networking/dhcpcd.nix`

2. **nixpkgs `networkmanager.nix` source** (nixos-25.05): confirms NM's internal DHCP client is independent of dhcpcd; `ensureProfiles` writes keyfile profiles to `/run/NetworkManager/system-connections/` and calls `nmcli connection reload`. URL: `https://github.com/NixOS/nixpkgs/blob/nixos-25.05/nixos/modules/services/networking/networkmanager.nix`

3. **NetworkManager keyfile spec** (`nm-settings-keyfile(5)`): confirms `type=bridge`, `controller=<master>`, `port-type=bridge` are the correct modern fields for bridge master/slave profiles. URL: `https://networkmanager.dev/docs/api/latest/nm-settings-keyfile.html`

4. **NixOS Wiki — Networking**: confirms that `networking.dhcpcd.enable = false` is the recommended way to disable dhcpcd, and that NetworkManager and scripted networking are separate backends. URL: `https://wiki.nixos.org/wiki/Networking`

5. **NixOS Wiki — Proxmox Virtual Environment**: describes cloud-init enabling `systemd-networkd` for NixOS-in-Proxmox (the inverse of our use case), confirming NM and networkd are alternative backends. URL: `https://wiki.nixos.org/wiki/Proxmox`

6. **proxmox-nixos `bridges.nix`** (SaumonNet/proxmox-nixos, main): the upstream Proxmox NixOS module's own bridge support writes `/etc/network/interfaces` for PVE's own bridge visibility, but explicitly states "This option has no effect on OS level network config" — confirming that OS-level bridge networking is the responsibility of the NixOS configuration, not proxmox-nixos. URL: `https://github.com/SaumonNet/proxmox-nixos/blob/main/modules/proxmox-ve/bridges.nix`

7. **NixOS Wiki — Networking (Link Aggregation / Bond via NM)**: shows a real `ensureProfiles.profiles` example for a bond master + slave, confirming the `ensureProfiles` pattern works for complex multi-interface configurations (bridges use the same structure). URL: `https://wiki.nixos.org/wiki/Networking#NetworkManager`

---

## 9. Summary

| Item | Value |
|------|-------|
| **Bug** | `vmbr0` gets no DHCP lease → host loses network on activation, Proxmox web UI unreachable |
| **Root cause** | `proxmox.nix` relies on dhcpcd for DHCP; `network.nix` forces dhcpcd off globally |
| **Fix** | Replace scripted-networking bridge block with NM `ensureProfiles` bridge + slave keyfile profiles |
| **Files changed** | `modules/server/proxmox.nix` only |
| **Architecture compliance** | Yes — change is in a role-specific module, no `lib.mkIf` guards added, no changes to shared base |
| **Risk level** | Low — brief connectivity loss during `nixos-rebuild switch` on live hosts only |
| **Spec file** | `.github/docs/subagent_docs/proxmox_dhcp_spec.md` |
