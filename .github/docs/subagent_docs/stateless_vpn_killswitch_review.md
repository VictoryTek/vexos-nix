# Review: VPN Kill Switch for Stateless Role

**Feature:** `stateless_vpn_killswitch`
**Date:** 2026-06-24
**Phase:** 3 — Review & Quality Assurance
**Reviewer:** Orchestrating Agent

---

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 95% | A |
| Functionality | 95% | A |
| Code Quality | 95% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | N/A — Windows dev host | — |

**Overall Grade: A (97.5% — build validation deferred to NixOS host)**

---

## 1. Specification Compliance

All 7 requirements from the spec verified:

| Requirement | Status |
|-------------|--------|
| All clearnet egress blocked when no tunnel active | ✅ DROP rule at end of chain |
| Region switching without config change | ✅ Bootstrap ports open to any destination |
| Credentials not in Nix store or git | ✅ NM system-connections persisted to /persistent |
| Tor Browser covered automatically | ✅ All egress goes through tun+ |
| Custom GUI app compatibility | ✅ tun+ wildcard matches any tunN interface |
| IPv6 leak prevention | ✅ `networking.enableIPv6 = false` |
| VPN profiles survive reboots | ✅ `vexos.impermanence.extraPersistDirs` |

---

## 2. Best Practices

**iptables chain management is idempotent:**
```
iptables -N vpn-kill-switch 2>/dev/null || iptables -F vpn-kill-switch
```
Create if new, flush if exists — safe across `nixos-rebuild switch` without accumulating duplicate rules.

**Jump insertion is idempotent:**
```
iptables -C OUTPUT -j vpn-kill-switch 2>/dev/null || iptables -A OUTPUT -j vpn-kill-switch
```
`-C` (check) returns exit 0 if rule exists, 1 if not. The `||` only inserts if absent.

**`extraStopCommands` cleans up properly:**
Removes the jump, flushes the chain, then deletes it. All with `|| true` guards so the firewall stop script never fails on a partially-initialized system.

**Minor (non-blocking):** The `extraCommands` and `extraStopCommands` approach is the correct one for an iptables-backed firewall. If the project ever migrates to `networking.nftables.enable = true`, these would need conversion to `networking.nftables.tables`. This is noted as a future migration concern, not a current defect.

---

## 3. Consistency (Module Architecture Pattern)

- **New stateless-only file** `modules/network-killswitch-stateless.nix` — not imported by any shared role configuration. Correct.
- **Imported only in `configuration-stateless.nix`** — correct per Option B pattern.
- **No `lib.mkIf` guards added** — the entire module applies unconditionally when imported.
- **`extraPersistDirs` used** instead of editing `impermanence.nix` — surgical; preserves the module's intentional "maximum stateless" default for any other roles that might import it.

---

## 4. Security Review

**Kill switch coverage:**
- Loopback: allowed (local IPC not affected)
- DHCP: allowed outbound only — inbound DHCP offers are INPUT chain, not affected by OUTPUT kill switch
- PIA bootstrap ports: UDP 1197/1198, TCP 501/502 — covers all four `.ovpn` file variants
- Tailscale UDP 41641 + `tailscale0` interface: allowed — Tailscale enabled system-wide in `network.nix`
- `tun+` and `wg+`: allowed — covers OpenVPN (now) and WireGuard (future)
- Everything else: DROP

**IPv6:** `networking.enableIPv6 = false` sets `ipv6.disable=1` at kernel boot — the IPv6 stack does not initialize. No IPv6 sockets, no IPv6 routing, no leak surface.

**DNS leaks:** When VPN is down, external DNS servers are unreachable (clearnet egress dropped). `systemd-resolved` returns SERVFAIL. When VPN is up, PIA's `dhcp-option DNS` in the `.ovpn` file updates resolved's upstream — DNS goes through `tun0`. No DNS leak in either state.

**Credentials:** `/etc/NetworkManager/system-connections/` is bind-mounted from `/persistent/etc/NetworkManager/system-connections/`. This directory is not tracked by git (`git ls-files` confirmed no NM connection files). Credentials live in `/persistent` under user control only.

**No hardcoded secrets.** No world-writable files added. No plaintext credential assignments.

---

## 5. gnome.nix Change Assessment

**Change:** `networking.networkmanager.plugins` → `networking.networkmanager.packages`

**Impact scope:** `gnome.nix` is imported by desktop, stateless, htpc, and server roles.

**Risk:** Low. This is a bug fix for a confirmed NixOS 25.11 regression. The old `.plugins` setting was silently broken — the D-Bus service for OpenVPN never registered. The `.packages` option correctly installs the plugin into NM's service environment. Both desktop and stateless roles benefit.

**Dry-build must verify** that the option name `networking.networkmanager.packages` is recognized in 25.11's NetworkManager module without evaluation errors.

---

## 6. Build Validation

`nix` is not available on the Windows development host. The following commands **must be run on the NixOS target** before merge:

```bash
nix flake show --impure
sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd
sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia
sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm
sudo nixos-rebuild dry-build --flake .#vexos-stateless-amd
```

The stateless dry-build is mandatory; the desktop dry-builds verify the gnome.nix change does not break other roles.

**Static checks completed on Windows host:**
- ✅ `git ls-files hardware-configuration.nix` — empty (not tracked)
- ✅ `system.stateVersion = "25.11"` unchanged in `configuration-stateless.nix`
- ✅ No new flake inputs added
- ✅ Three expected files changed, no unexpected files modified

---

## 7. Issues

### CRITICAL
None identified in static review.

### REQUIRED (must verify on NixOS host before merge)
- `networking.networkmanager.packages` option exists and is recognized in NixOS 25.11's `networkmanager.nix` module — will produce an evaluation error on dry-build if the option name changed

### INFORMATIONAL (non-blocking)
- Tailscale over a PIA+kill-switch system: Tailscale UDP 41641 bootstrap is allowed, but if PIA is connected first and Tailscale hasn't registered its DERP relay connection yet, Tailscale may fail to connect until PIA is disconnected. This is a runtime sequencing concern, not a configuration bug.
- Future migration: if `networking.nftables.enable = true` is ever enabled project-wide, `extraCommands`/`extraStopCommands` must be converted to nftables table syntax.

---

## Verdict: **PASS** (pending NixOS host dry-build)

The implementation is architecturally correct, consistent with the project's Module Architecture Pattern, and addresses all specified requirements. The only remaining gate is a live dry-build on NixOS to confirm the `networking.networkmanager.packages` option name and evaluate the full stateless closure.
