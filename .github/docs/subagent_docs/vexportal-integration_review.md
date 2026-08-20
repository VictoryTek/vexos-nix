# VexPortal Integration — Review

## Specification compliance

All 5 tasks from `vexportal-integration_spec.md` implemented as specified:

- Task 1: `_confirm` private recipe added (`justfile:1227`); 5 call sites migrated
  (`switch`, `set-hostname`, `fix-flake`, `reset-defaults`, `restore-plex`). Verified
  `VEXOS_ASSUME_YES=1` short-circuits to `true`; unset + `y`/`n`/EOF all match original
  case-statement semantics.
- Task 2: `update role="" variant=""` added; interactive prompt only entered when the
  corresponding param is empty AND `/etc/nixos/vexos-variant` is absent. Verified via
  `just --dump --dump-format json`.
- Task 3: `setup-rdp` branches on `[ -t 0 ]` — TTY path unchanged, non-TTY path reads one
  line, no confirmation.
- Task 4: audited, no code change — documented in spec (disk selection / ZFS pool
  creation / arr multi-select are not simple scalar values; `enable` correctly stays
  `terminal = true` in VexPortal's catalog).
- Task 5: `vexportal` input + `vexportalModule` added to `flake.nix`, wired into
  `baseModules` for desktop/htpc/stateless/server only (matches `upModule`'s role set
  exactly; headless-server and vanilla excluded).

## Best practices / consistency

- `_confirm` follows the existing `just _resolve-flake-dir` command-substitution helper
  pattern already used in this justfile — no new idiom introduced.
- `vexportalModule` mirrors `upModule`'s shape and placement exactly; `roles` table
  entries touched only by appending `vexportalModule` next to `upModule`, no other lines
  changed.
- No `lib.mkIf` role-gating introduced in shared Nix modules (N/A — no `modules/*.nix`
  files touched).

## Build validation

- `nix flake show --impure`: PASS — 30 `nixosConfigurations` + all `nixosModules` +
  `packages.x86_64-linux` listed without evaluation errors.
- `nix eval --impure` full-toplevel evaluation (CI-equivalent, `sudo` unavailable in this
  sandbox — see note below): PASS for `vexos-desktop-amd`, `vexos-desktop-nvidia`,
  `vexos-desktop-vm`.
- `vexos-server-amd` / `vexos-headless-server-amd` full-toplevel evaluation fails on a
  **pre-existing, unrelated** assertion: `networking.hostId` is still the shared
  placeholder in `hosts/server-amd.nix:15` (`lib.mkDefault "a0000001"`), guarded by a ZFS
  hostId assertion. Confirmed via `git diff --stat hosts/ modules/` — this work touched
  neither directory. Isolated re-check of just `config.programs.vexportal.enable` on both
  targets confirms the vexportal wiring itself evaluates cleanly (`true` on
  `vexos-server-amd`; attribute correctly absent — not merely `false` — on
  `vexos-headless-server-amd`, since `vexportalModule` isn't in that role's
  `baseModules`).
- `programs.vexportal.enable` spot-checked across all touched roles: `true` on
  desktop-amd/nvidia, htpc-amd, stateless-amd, server-amd; attribute **does not exist**
  on headless-server-amd or vanilla-amd (module not imported — correct, not a
  false-but-present value).
- `git ls-files hardware-configuration.nix`: empty (not tracked) — PASS.
- `system.stateVersion` present, unchanged in all 6 `configuration-*.nix` — PASS.
- `flake.nix` new input `vexportal` declares `inputs.nixpkgs.follows = "nixpkgs"` — PASS.
- `scripts/preflight.sh`: **exit code 0**, "Preflight PASSED — safe to push." Pre-existing
  repo-wide `nixpkgs-fmt` WARN (96/187 files, unrelated to the 2 files this work touched)
  and flake.lock age WARNs do not fail the script and are unrelated to this change.
- Justfile: `just --dump --dump-format json` succeeds (valid syntax); `bash -n` on every
  modified recipe's dry-run output (`setup-rdp`, `reset-defaults`, `restore-plex`,
  `switch`, `set-hostname`, `fix-flake`, `update`) passes.

**Note on `sudo nixos-rebuild dry-build`:** not runnable in this execution environment —
`sudo` is blocked here (container policy, "no new privileges" flag), not a NixOS host.
Substituted with `nix eval --impure
.#nixosConfigurations.<target>.config.system.build.toplevel.drvPath`, which CLAUDE.md
documents as the CI-equivalent full-evaluation check. This forces the same option
resolution and assertion evaluation `dry-build` would (up to but not including the
actual build step), which is what a justfile/flake-wiring-only change needs validated.

## Security

No secrets introduced or touched. `setup-rdp` still never accepts the password via env
var or argument (stdin only), consistent with the existing `/etc/nixos/secrets`
0600-root:root pattern.

## Completeness

All 5 tasks addressed. Human-terminal behavior verified unchanged by construction: every
prompt call site preserves its original text and case-statement branches; `_confirm`
only special-cases `VEXOS_ASSUME_YES=1`, otherwise reduces to the original `read -r` +
case logic.

## Score table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 100% | A |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | N/A | — |
| Consistency | 100% | A |
| Build Success | 100% (pre-existing unrelated hostId assertion excluded) | A |

**Overall Grade: A (100%)**

## Result: PASS
