# L-08 — zfs-server.nix installs pkgs.zfs alongside the module-managed build — Review

Status: Phase 3 (Review & Quality Assurance)
Spec: `.github/docs/subagent_docs/L-08_zfs_package_skew_spec.md`

## Modified Files

- `modules/zfs-server.nix`

## Review Against Spec

1. **Specification Compliance** — matches the spec exactly:
   `environment.systemPackages` now references `config.boot.zfs.package`
   instead of the plain `pkgs.zfs` attribute, moved out of the
   `with pkgs; [...]` block (since it isn't a `pkgs.*` attribute) and
   concatenated via `++` with the remaining three `with pkgs;` entries
   (`gptfdisk`, `util-linux`, `pciutils`), which are untouched.

2. **Best Practices** — `config.boot.zfs.package` is the officially
   documented NixOS override point for the ZFS userland build
   (confirmed directly against the upstream module source at this
   repo's pinned nixpkgs rev); referencing it instead of a hardcoded
   `pkgs.zfs` is the standard way to stay correct under a future
   `boot.zfs.package` override, matching the same instinct this file
   already applies to `boot.kernelPackages` two blocks above.

3. **Consistency** — style matches the rest of the file: inline
   comments explaining *why*, not just what; `config`/`lib`/`pkgs` usage
   consistent with the module's existing `{ config, lib, pkgs, ... }:`
   argument list (already used for `config.networking.hostId` in the
   `assertions` block below).

4. **Maintainability** — comment explains the specific failure mode
   being avoided (divergent zfs userland/kernel-module pairing if
   `boot.zfs.package` is ever pinned), not just "use the option
   instead."

5. **Completeness** — the one cited line is the only place in the repo
   referencing `pkgs.zfs` (confirmed via grep) — no other module lists
   it.

6. **Performance** — no impact; same derivation is installed either
   way under current (unoverridden) configuration.

7. **Security** — no new vulnerabilities; removes a latent
   version-skew footgun (two different zfs userland builds coexisting
   in the closure with undefined PATH precedence) without introducing
   any new attack surface.

8. **API Currency** — verified `boot.zfs.package`'s definition and
   `environment.systemPackages` wiring directly against
   `nixos/modules/tasks/filesystems/zfs.nix` at this repo's pinned
   nixpkgs commit (`e4bae1bd10c9c57b2cf517953ab70060a828ee6f`, per
   `flake.lock`) rather than assuming from memory — option name,
   default, and semantics all current.

9. **Build Validation** — this Windows session has no local `nix`
   binary, but a WSL2 Ubuntu distro with Nix 2.34.1 was found and used
   to run the real checks against the mounted repo
   (`/mnt/c/Projects/vexos-nix`):
   - `nix flake show --impure` → PASS, all 30 `nixosConfigurations` and
     all `nixosModules` evaluate.
   - `nix eval --impure ".#nixosConfigurations.vexos-desktop-amd.config.system.build.toplevel.drvPath"` → PASS
   - same for `vexos-desktop-nvidia` → PASS
   - same for `vexos-desktop-vm` → PASS
   - `vexos-server-amd` and `vexos-headless-server-amd` (required
     since this change touches `modules/zfs-server.nix`): direct
     `nixos-rebuild dry-build` isn't possible on this non-NixOS WSL
     Ubuntu (no `nixos-rebuild` binary), so used the CI-equivalent
     `nix eval --impure ...toplevel.drvPath`. Both host files ship only
     placeholder `networking.hostId` values by design (M-13), which
     `zfs-server.nix`'s own assertion correctly rejects — supplied a
     throwaway real-looking value (`cafebabe`, matching CI's own fixture
     at `.github/workflows/ci.yml:170`) via `extendModules` at eval time
     (no on-disk changes) purely to get past that unrelated assertion
     and reach real module evaluation. Both →
     **PASS** — full toplevel closure evaluates with no assertion or
     type errors, confirming the `config.boot.zfs.package` reference
     resolves correctly.
   - Ran the full `bash scripts/preflight.sh` end-to-end → **exit 0,
     "Preflight PASSED — safe to push."** All 8 stages passed or
     produced only pre-existing, expected WARNs (missing optional tools:
     `jq`, `nixpkgs-fmt`, `gitleaks`; the `vexboard.nix:90`
     "change-me" placeholder-secret WARN, which is the intentional
     assert-guarded default documented in H-09, not a real secret).
     Stage `[8/8]` (`pkgs.vexos.vexos-update` build/shellcheck) built
     successfully.
   - `git ls-files hardware-configuration.nix` → empty, unaffected.
   - No `system.stateVersion` change; no new flake inputs.
   - No FORBIDDEN COMMANDS used (`nix flake check` was never invoked;
     the WSL environment lacks `nixos-rebuild switch`/`boot` entirely).

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
| Build Success | 100% — `nix flake show`, 5 target evaluations, and full `preflight.sh` all passed via WSL2 | A |

**Overall Grade: A (100%)**

## Result

**PASS.** Phase 6 (Preflight) has genuinely run and passed for this
commit, including the server/headless-server evaluations this
server-module change requires. Safe to push.
