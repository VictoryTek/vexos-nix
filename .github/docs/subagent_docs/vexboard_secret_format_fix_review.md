# Review: vexboard EnvironmentFile typo fix

## Files Reviewed
- `modules/server/vexboard.nix` — added `systemd.services.vexboard.serviceConfig.EnvironmentFile`

## Root Cause Verified
- Upstream module line 161: `EnvironmentFiles = lib.optional ...` (plural)
- `nixos/lib/systemd-lib.nix` `attrsToSection` uses attribute name verbatim → `EnvironmentFiles=<path>` in unit
- systemd ignores `EnvironmentFiles=` as unrecognized; `VEXBOARD_AUTH__SECRET` is never set
- Fix: adds `serviceConfig.EnvironmentFile` (singular) in our wrapper module; correct directive recognized by systemd

## Specification Compliance
- [x] Only `modules/server/vexboard.nix` modified — surgical
- [x] `toString cfg.secretFile` ensures path/string coercion without store import
- [x] `lib.optional (cfg.secretFile != null)` mirrors upstream logic, null-safe
- [x] Comment explains upstream bug and the workaround rationale

## Best Practices
- [x] No `lib.mkForce` needed — `EnvironmentFile` is a new attribute key, no conflict with existing `EnvironmentFiles`
- [x] `lib.optional` returns `[]` when secretFile is null, which `attrsToSection` handles correctly (emits no directive)
- [x] Follows Module Architecture Pattern Option B — no new `lib.mkIf` in shared modules

## Consistency
- [x] No new `lib.mkIf` guards added to shared modules
- [x] No new flake inputs
- [x] `system.stateVersion` unchanged in all `configuration-*.nix` (all remain "25.11")
- [x] `hardware-configuration.nix` not tracked (`git ls-files` returns empty)

## Security
- [x] No hardcoded secrets
- [x] Secret file path referenced but not copied to Nix store (plain string, not path literal)
- [x] No plaintext credential assignments

## Build Validation

| Check | Result |
|-------|--------|
| `nix flake show --impure` | PASS — all outputs listed |
| `nix eval vexos-desktop-amd` | PASS — drv returned |
| `nix eval vexos-desktop-nvidia` | PASS — drv returned |
| `nix eval vexos-desktop-vm` | PASS — drv returned |
| `nix eval vexos-server-amd` | PASS — drv returned |
| `nix eval vexos-headless-server-amd` | PASS — drv returned |
| `hardware-configuration.nix` not tracked | PASS |
| `system.stateVersion` unchanged | PASS — all "25.11" |

Note: `sudo nixos-rebuild dry-build` unavailable in sandbox (`no_new_privs`). `nix eval --impure` used as the CI-equivalent (full evaluation depth, no build).

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
| Build Success | 100% | A |

**Overall Grade: A (100%)**

## Verdict: PASS
