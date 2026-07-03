# H-18 — Review & Quality Assurance

Status: Phase 3 (Review)
Spec: `.github/docs/subagent_docs/H-18_mkBaseModule_refactor_spec.md`

## Modified Files

- `flake.nix` — `mkBaseModule` now reads `roles.${role}.baseModules` directly instead of
  re-deriving overlay/upModule/proxmox/sops/vexboard membership three separate ways.
  Updated the stale comment above it that described the old (now-removed) divergences.

## Review Findings

1. **Specification Compliance** — implements exactly the spec's proposed `mkBaseModule`
   body; no other function touched.
2. **Best Practices** — eliminates duplicated logic in favor of a single source of truth
   (`roles` table), which is the stated purpose of that table's own doc comment.
3. **Consistency** — `nixosConfigurations` (`mkHost`/`hostList`) completely untouched;
   confirmed by identical `.drv` hashes before/after this change for every evaluated
   target (see Build Validation).
4. **Maintainability** — future edits to `roles.<role>.baseModules` now automatically
   apply to both `mkHost` and `mkBaseModule`; no third copy to remember to update.
5. **Completeness** — all three duplicated blocks named in the spec were removed.
6. **Performance** — no change (same modules, just referenced once instead of
   re-derived).
7. **Security** — no secrets/credentials involved.
8. **API Currency** — n/a, pure internal refactor, no external library surface.
9. **Build Validation:**
   - `nix flake show --impure` — passed, all outputs still enumerate.
   - Required targets (`vexos-desktop-amd`, `vexos-desktop-nvidia`, `vexos-desktop-vm`,
     `vexos-server-amd`, `vexos-headless-server-amd`) plus `vexos-htpc-amd`,
     `vexos-stateless-amd`, `vexos-vanilla-amd` (broader set since this is a
     `flake.nix`-level change) all evaluated via
     `nix eval --impure ".#nixosConfigurations.<x>.config.system.build.toplevel.drvPath"`.
     **Every resulting `.drv` hash is byte-identical to the pre-change run** — direct
     proof `mkHost`/`hostList` behavior is completely unaffected, which is the intended
     minimal blast radius for this refactor.
   - Built synthetic `nixosSystem`s directly consuming each `nixosModules.*Base` output
     (mirroring how `template/etc-nixos-flake.nix` consumes them, with a stub
     `hardware-configuration.nix`) to verify the actual bug fix and the three
     "divergence" behaviors that used to be hand-derived:
     - `vanillaBase`: `nixpkgs.overlays` count went from 2 (unstable + custom-pkgs,
       present before this fix) to **0** — confirms the vanilla overlay leak (the core
       H-18 bug) is fixed. `pkgs.unstable`/`pkgs.vexos` are correctly absent.
     - `serverBase`/`headlessServerBase`: `pkgs.unstable` and `pkgs.vexos` (custom
       packages overlay) both present, as they were before — no regression.
     - `up.packages.x86_64-linux.default` presence in `environment.systemPackages`:
       present for `serverBase`, absent for `headlessServerBase` and `vanillaBase` —
       matches the `roles` table exactly (previously this was a hand-written string
       predicate that happened to match; now it's derived directly).
   - `git ls-files hardware-configuration.nix` — empty. ✓
   - `system.stateVersion` — untouched. ✓
   - `flake.nix` inputs (`url`/`follows` lines) — untouched; confirmed via `git diff`. ✓
   - `bash scripts/preflight.sh` — exit 0, PASSED. Same pre-existing WARNs as prior
     reviews in this session; nothing new.

No CRITICAL or RECOMMENDED issues found.

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

## Returns

- Build result: PASS
- **PASS**
