# Review: Toggleable VPN Kill Switch Service

**Feature:** `killswitch_service`
**Date:** 2026-06-24
**Phase:** 3 — Review & Quality Assurance

---

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 100% | A |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | N/A — Windows dev host | — |

**Overall Grade: A (100% — build validation deferred to NixOS host)**

---

## 1. Specification Compliance

All requirements verified:

| Requirement | Status |
|-------------|--------|
| Toggleable at runtime without rebuild | ✅ systemd oneshot service, not wantedBy anything |
| Same kill switch rules as stateless module | ✅ Identical rule set |
| IPv6 disabled | ✅ `networking.enableIPv6 = false` |
| Polkit rule for passwordless toggle | ✅ Scoped to `vpn-kill-switch.service` start/stop |
| `just enable-kill-switch` recipe | ✅ Added to justfile |
| `just disable-kill-switch` recipe | ✅ Added to justfile |
| Imported by desktop and HTPC configurations | ✅ Both configs updated |

---

## 2. Service Design

**`Type = oneshot` + `RemainAfterExit = true`** is the correct pattern for a
one-shot firewall rule installer — systemd tracks the service as "active" after
`ExecStart` completes until `ExecStop` is called.

**`after = [ "firewall.service" ]`** — correct startup ordering: if both activate
simultaneously, firewall loads first and our rules append on top of it.

**`partOf = [ "firewall.service" ]`** — if the NixOS firewall service restarts
during a `nixos-rebuild switch`, this service is also restarted. The rules are
re-applied after the new firewall rules load. Without this, a rebuild that touches
any firewall option would silently clear the kill switch rules while leaving the
service reporting "active".

**Not in `wantedBy`** — service is inactive until explicitly started. Correct: this
is a user-opt-in kill switch, not an always-on constraint.

---

## 3. Script Safety

**`startScript`**: uses absolute `${pkgs.iptables}/bin/iptables` paths — no PATH
dependency in the service execution context. Chain creation is idempotent
(`-N ... || -F ...`). OUTPUT jump insertion is idempotent (`-C ... || -A ...`).

**`stopScript`**: all three commands guarded with `2>/dev/null || true` — safe if
the chain was already cleaned up (e.g., by an emergency `iptables -F`).

---

## 4. Security Review

**Polkit rule scope**: restricted to `action.id === "org.freedesktop.systemd1.manage-units"`,
exact `unit === "vpn-kill-switch.service"`, and only `verb === "start"` or `"stop"`.
No other units or verbs are affected. No privilege escalation beyond the intended toggle.

**Group check**: `subject.isInGroup("users")` — matches the standard group that all
interactive users on vexos belong to (set in `modules/users.nix`).

**No hardcoded secrets.** No world-writable files. No plaintext credentials.

---

## 5. Justfile Recipes

`enable-kill-switch`: guards on `*stateless*` variant and prints an informative
message rather than failing. Calls `systemctl start` directly — works because
the polkit rule grants the permission without sudo.

`disable-kill-switch`: same guard pattern. On stateless, exits with code 1 and
an explanation — correct behavior since disabling is not allowed there.

Both recipes follow the established justfile style: `#!/usr/bin/env bash`,
`set -euo pipefail`, variant detection from `/etc/nixos/vexos-variant`.

---

## 6. Module Architecture Compliance

- New file `modules/network-killswitch-service.nix` — not imported by any shared
  module. Correct per Option B pattern.
- Imported only by `configuration-desktop.nix` and `configuration-htpc.nix`.
- `configuration-stateless.nix` is unchanged — still uses the always-on
  `extraCommands` approach via `network-killswitch-stateless.nix`.
- No `lib.mkIf` guards added anywhere.

---

## 7. Static Checks

- ✅ `git ls-files hardware-configuration.nix` — empty (not tracked)
- ✅ `system.stateVersion = "25.11"` unchanged in `configuration-desktop.nix`
- ✅ `system.stateVersion = "25.11"` unchanged in `configuration-htpc.nix`
- ✅ No new flake inputs added
- ✅ Five expected files changed/created; no unexpected files modified

---

## 8. Build Validation (required on NixOS host)

```bash
nix flake show --impure
sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd
sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia
sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm
sudo nixos-rebuild dry-build --flake .#vexos-htpc-amd
```

Key items to verify:
- `systemd.services.vpn-kill-switch` evaluates without attribute errors
- `security.polkit.extraConfig` JS string is accepted
- `partOf = [ "firewall.service" ]` is recognized as a valid list attribute

---

## 9. Issues

### CRITICAL
None.

### REQUIRED (verify on NixOS host before merge)
- Confirm `partOf` attribute is valid in `systemd.services` (NixOS 25.11) —
  it is a standard NixOS systemd service option but worth confirming on dry-build

### INFORMATIONAL
- If the user starts the kill switch and then runs `just rebuild` on a config that
  restarts the firewall, the `PartOf` relationship will restart and re-enable the
  kill switch. This is correct and desired behavior.

---

## Verdict: **PASS** (pending NixOS host dry-build)
