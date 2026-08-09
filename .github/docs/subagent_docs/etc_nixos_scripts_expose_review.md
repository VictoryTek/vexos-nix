# Review — Expose `scripts/` under `/etc/nixos/scripts`

## Scope

Reviewed against spec: `.github/docs/subagent_docs/etc_nixos_scripts_expose_spec.md`
Modified file: `modules/packages-common.nix` (single line added)

## Findings

1. **Specification Compliance** — Implementation matches spec exactly: one
   `environment.etc."nixos/scripts".source = ../scripts;` line added immediately after
   the existing justfile etc line. No other files touched.
2. **Best Practices** — Standard `environment.etc` directory-source pattern, already used
   in this same file for `template/server-services.nix` and `template/features.nix`.
3. **Consistency (Module Architecture Pattern)** — `packages-common.nix` remains a
   universal base file with no role-gated `lib.mkIf`; the new line applies
   unconditionally to every role that imports it, same as the pre-existing lines. No
   architectural deviation.
4. **Maintainability** — Trivial, self-explanatory addition; existing comment above it
   already documents the etc-exposure rationale and applies equally to the new line.
5. **Completeness** — Fixes the `/etc/nixos/scripts` fallback candidate already checked
   by `create-zfs-pool` (justfile:1266) and the shared `_run-storage-script` helper
   (justfile:1306), used by `create-mergerfs-pool` and `attach-remote-storage`. All three
   recipes benefit from this one change.
6. **Performance** — Negligible closure/activation impact; `scripts/` is a small
   directory of shell/python scripts.
7. **Security** — Scanned `scripts/` for hardcoded secrets/credentials; none found (only
   interactive password-prompt references in setup scripts, no plaintext assignments).
   No world-writable files introduced — `environment.etc` sources are read-only store
   paths by construction.
8. **API Currency** — N/A, no external library/dependency involved.
9. **Build Validation:**
   - `nix flake show --impure` — passed, all 30 `nixosConfigurations` + module outputs
     listed with no evaluation errors.
   - `sudo nixos-rebuild dry-build` is unavailable in this sandbox (`sudo` blocked by
     `no-new-privileges`), so per CLAUDE.md's listed CI-equivalent alternative, ran
     `nix eval --impure ".#nixosConfigurations.<cfg>.config.system.build.toplevel.drvPath"`
     for each required target instead:
     - `vexos-desktop-amd` — PASS (drvPath resolved)
     - `vexos-desktop-nvidia` — PASS
     - `vexos-desktop-vm` — PASS
     - `vexos-stateless-amd` — PASS (pre-existing, unrelated locked-password eval
       warning only)
     - `vexos-htpc-amd` — PASS
     - `vexos-server-amd` — FAILED on `networking.hostId` placeholder assertion
       (`modules/zfs-server.nix:85-97`)
     - `vexos-headless-server-amd` — FAILED on the same assertion
   - **Root-caused the two failures as pre-existing and unrelated to this change:**
     `hosts/server-amd.nix:15` commits a shared placeholder hostId
     (`lib.mkDefault "a0000001"`), which `modules/zfs-server.nix`'s assertion
     deliberately rejects by design — real per-machine values are only supplied via
     `hostModule` in the deployed host's `/etc/nixos/flake.nix` (substituted by
     `install.sh`), not in this shared dev repo. This assertion fires identically
     regardless of the `packages-common.nix` change; confirmed by inspecting the
     assertion condition and hostId source directly (`git stash` was not used — user
     denied that tool call — but the assertion list/message make the unrelated,
     pre-existing nature unambiguous: it checks against 8 specific committed
     placeholder strings that have nothing to do with `environment.etc`).
   - Confirmed `git ls-files hardware-configuration.nix` returns empty (not committed).
   - Confirmed no `configuration-*.nix` files changed (`stateVersion` untouched).
   - Confirmed no `flake.nix` changes (no new flake inputs to check `follows` on).

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
| Build Success | 100%* | A |

\* Desktop/stateless/htpc/vm variants evaluate cleanly with the change. Server /
headless-server variants fail on a pre-existing, unrelated `networking.hostId`
placeholder assertion that is independent of this change and expected when evaluating
those roles from this shared dev repo rather than a real per-machine host.

**Overall Grade: A (100%)**

## Result

**PASS** — no refinement needed.
