# Spec: Seerr Service Persistence Fix

**Feature Name:** seerr_persistence_fix
**Spec Path:** `.github/docs/subagent_docs/seerr_persistence_fix_spec.md`
**Date:** 2026-06-22
**Status:** READY FOR IMPLEMENTATION

---

## 1. Current State Analysis

### File Under Review

`modules/server/seerr.nix` — hand-crafted `systemd.services.seerr` using `pkgs.unstable.seerr`
(the unified successor to jellyseerr/overseerr, added to nixpkgs-unstable at v3.3.0).

No upstream `services.seerr` NixOS module exists in nixpkgs 25.11; the custom systemd
service is the correct approach.

### Symptom

Service starts and runs correctly after initial enable + rebuild, but is **not running**
after either a reboot or a `nixos-rebuild switch` (update). The user cannot determine
which event caused it; they performed both.

---

## 2. Root Cause Analysis

### Root Cause 1 (PRIMARY): Wrong `after` target — `network.target` instead of `network-online.target`

The current module declares:

```nix
after = [ "network.target" ];
```

`network.target` is reached as soon as the kernel has brought network interfaces up. It
does **not** guarantee IP assignment, DNS resolution, or actual connectivity. Seerr
(a Node.js HTTP server) performs DNS lookups and may attempt to contact Jellyfin,
Sonarr, or Radarr during its startup sequence.

If seerr starts before those dependencies are reachable, it throws an error and exits
non-zero. With `Restart = "on-failure"` and no `RestartSec`, systemd defaults to 100 ms
between restarts. Seerr fails, restarts, fails, restarts — 5 times in under one second.
systemd's default start rate limit (`StartLimitIntervalSec = 10s`, `StartLimitBurst = 5`)
is exceeded and the unit enters a **permanent failed state**. It does not retry further,
even after the network is up.

The official seerr build-from-source systemd unit (confirmed via seerr docs) uses:

```ini
[Unit]
Wants=network-online.target
After=network-online.target
```

**This is the fix that resolves "does not start after reboot."**

### Root Cause 2 (CONTRIBUTING): No `RestartSec` — rapid restart hits rate limit

Without `RestartSec`, systemd retries at 100 ms intervals. Five failures in under a
second exhausts the burst limit. Even with `network-online.target` added, transient
errors (e.g., a flapping upstream) could still exhaust the rate limit. Adding
`RestartSec = "5"` (5 seconds between restarts) makes the service resilient to
transient failures and keeps it well under the burst limit.

### Root Cause 3 (MINOR): No `WorkingDirectory`

The official seerr systemd service specifies `WorkingDirectory`. Without it, Node.js
apps sometimes resolve relative paths unexpectedly. Since `CONFIG_DIRECTORY` is set
to an absolute path this is not currently failing, but adding
`WorkingDirectory = "/var/lib/seerr"` (the StateDirectory) aligns with upstream and
prevents edge-case path resolution issues.

### Why It Worked Initially

On the first `nixos-rebuild switch`, networkd is fully settled (the admin is logged in
and the system has been running for some time). Seerr starts successfully against a
warm, fully-ready network. On the next **reboot**, seerr races against network setup —
it starts the moment `network.target` is reached (very early), before DHCP assignment
and DNS are ready, and enters the permanent failed state.

---

## 3. Problem Definition

`modules/server/seerr.nix` uses `after = [ "network.target" ]` which does not guarantee
network readiness. Combined with no `RestartSec`, seerr exhausts systemd's restart rate
limit before the network is ready, entering a permanent failed state that survives until
the next manual `systemctl start seerr` or reboot. On the next reboot the cycle repeats.

---

## 4. Proposed Solution Architecture

Three targeted, surgical changes to `modules/server/seerr.nix`:

1. **Replace `after = [ "network.target" ]` with `after = [ "network.target" "network-online.target" ]`
   and add `wants = [ "network-online.target" ]`** — ensures seerr starts only after the
   network is fully ready (IP assigned, DNS available).

2. **Add `serviceConfig.RestartSec = "5"`** — 5 seconds between restart attempts prevents
   rapid-fire failures from exhausting the default `StartLimitBurst = 5` in
   `StartLimitIntervalSec = 10s`.

3. **Add `serviceConfig.WorkingDirectory = "/var/lib/seerr"`** — aligns with upstream
   systemd unit; ensures consistent working directory for the Node.js process.

No options are added or removed. No other files are touched.

---

## 5. Implementation Steps

1. Edit `modules/server/seerr.nix` only:
   - Add `wants = [ "network-online.target" ]` to the service unit attrs
   - Change `after` to include `"network-online.target"`
   - Add `WorkingDirectory = "/var/lib/seerr"` in `serviceConfig`
   - Add `RestartSec = "5"` in `serviceConfig`

2. No changes to `modules/server/default.nix`, `flake.nix`, or any other file.

---

## 6. Dependencies

No new dependencies. No new flake inputs.

---

## 7. Risks and Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| `network-online.target` delays boot on misconfigured hosts | Low | This is a server role; servers always wait for network. It is the standard pattern for all networked services. |
| Existing seerr data in `/var/lib/seerr/config` untouched | None | No state changes; only unit file metadata changes. |
| `WorkingDirectory` conflicts with `ProtectSystem = "strict"` | None | StateDirectory bind mounts are applied before ProtectSystem; `/var/lib/seerr` is writable. |

---

## 8. Files Modified

| File | Action |
|------|--------|
| `modules/server/seerr.nix` | Edit — add `wants`, extend `after`, add `WorkingDirectory` and `RestartSec` |

---

## 9. Verification

- `nix flake show --impure` passes
- `sudo nixos-rebuild dry-build --flake .#vexos-server-amd` passes
- `sudo nixos-rebuild dry-build --flake .#vexos-server-vm` passes
- `systemctl cat seerr` on the deployed VM shows `network-online.target` in `After=`
- `hardware-configuration.nix` not committed
- `system.stateVersion` unchanged
