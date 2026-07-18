# RDP Keyring / gnome-remote-desktop Restart — Review

**Feature:** `rdp_keyring_grd_restart`
**Reviewed file:** `modules/remote-desktop.nix`
**Spec:** `.github/docs/subagent_docs/rdp_keyring_grd_restart_spec.md`
**Date:** 2026-07-18

## Summary

The implementation adds the single missing step identified in the spec: after the
setup service unlocks the keyring (`gnome-keyring-daemon --replace`) and applies all
`grdctl` configuration including `set-credentials`, it now restarts the user
`gnome-remote-desktop.service` so the daemon rebinds its Secret Service connection to
the live keyring. `pkgs.systemd` was added to the service `path` for `systemctl`.
The module header and an inline comment document why the restart is required.

## Review Findings

1. **Specification Compliance** — Matches the spec exactly: path entry added, restart
   added as the final script step (after `disable-view-only`), header comment updated.
   No `grdctl --system` switch, no `--replace` removal — scope held.
2. **Best Practices** — Uses the same `runuser -u <user> -- env HOME=… DBUS_… XDG_…`
   invocation pattern as every other session-context call in the script; consistent
   and correct. `systemctl --user restart` starts the unit if not running.
3. **Consistency (Option B)** — Change is unconditional inside a universal base
   module; no new `lib.mkIf`, no role gating. Compliant.
4. **Maintainability** — Rationale documented in both the header block and inline at
   the call site; a future reader understands why the restart exists.
5. **Completeness** — Resolves the verified root cause of the "The name is not
   activatable" credential-retrieval failure on auto-login hosts.
6. **Performance** — One extra `systemctl` invocation at boot; negligible.
7. **Security** — No secrets added; no new world-readable material; password handling
   unchanged. `pkgs.systemd` already in closure. No plaintext credential assignment.
8. **API Currency** — `grdctl` 50.1 verified in-tree; `systemctl --user restart`
   is stable API. Matches the current upstream auto-login recipe.
9. **Build Validation**
   - `nix flake show --impure` → exit 0 (structure valid).
   - `sudo nixos-rebuild dry-build` unavailable in this sandbox (no-new-privileges);
     used the sanctioned CI-equivalent `nix eval … toplevel.drvPath`:
     - `vexos-desktop-amd` → drvPath produced, exit 0
     - `vexos-desktop-nvidia` → drvPath produced, exit 0
     - `vexos-desktop-vm` → drvPath produced, exit 0
   - `git ls-files hardware-configuration.nix` → empty (not committed).
   - No `configuration-*.nix` / `system.stateVersion` changes.
   - No new flake inputs.

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 95% | A |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 100% | A |

**Overall Grade: A (99%)**

## Result

Build: PASS (evaluation of all three desktop variants succeeded).
Verdict: **PASS** — no CRITICAL or RECOMMENDED issues. Proceed to Phase 6 Preflight.

Note: final runtime confirmation (RDP connects after `nixos-rebuild switch` + reboot on
`vexos-vmc`) is a user-initiated deploy step, since `nixos-rebuild switch` is a
FORBIDDEN (user-only) command.
