# H-19 — Review & Quality Assurance

Status: Phase 3 (Review)
Spec: `.github/docs/subagent_docs/H-19_builder_state_leak_spec.md`

## Modified Files

- `flake.nix` — added `roles.<role>.hostLocalModules` field (holding
  `featuresModule`/`serverServicesModule`/`statelessUserOverrideModule` per role,
  moved out of `extraModules`); `mkHost` now includes
  `r.extraModules ++ r.hostLocalModules` in the position `r.extraModules` alone
  previously held; `mkBaseModule` unchanged (already only reads
  `roles.${role}.extraModules` post-H-18, so it never picks up
  `hostLocalModules`). Updated doc comments explaining the split and why.

## Review Findings

1. **Specification Compliance** — matches the spec: two named modules moved as
   requested, `featuresModule` folded in for consistency (documented rationale in the
   spec — same defect shape, same file already has the equivalent host-side check).
2. **Best Practices** — the fix pushes impure filesystem checks to exactly the layer
   where "builder machine == target host" is actually guaranteed (`mkHost`, direct
   repo-checkout deployment), and removes them from the layer where that guarantee
   doesn't hold (`mkBaseModule`, consumed by a separate host-side flake that already
   does its own equivalent check).
3. **Consistency (Module Architecture Pattern)** — pure `flake.nix`-internal
   restructuring; no NixOS module (`modules/*.nix`) touched, no new `lib.mkIf` in any
   shared module.
4. **Maintainability** — the `roles` table's own doc comment now explains the
   `extraModules` vs `hostLocalModules` distinction, so the next person adding a role
   won't have to reverse-engineer which category their module belongs in.
5. **Completeness** — all three impure modules addressed; `mkHost` and `mkBaseModule`
   both handled per the spec.
6. **Performance** — no change.
7. **Security** — no change; no secrets involved.
8. **API Currency** — n/a.
9. **Build Validation:**
   - `nix flake show --impure` — passed.
   - Full required-plus-broader target set (`vexos-desktop-amd`, `-nvidia`, `-vm`,
     `vexos-server-amd`, `vexos-headless-server-amd`, `vexos-htpc-amd`,
     `vexos-stateless-amd`, `vexos-vanilla-amd`) evaluated via `nix eval --impure
     ".#nixosConfigurations.<x>.config.system.build.toplevel.drvPath"`.
     **Every `.drv` hash is byte-identical to the pre-change baseline** — direct proof
     `mkHost`'s real-deployment behavior (the repo-checkout `just switch`/`just build`
     path) is completely unaffected by moving these modules into `hostLocalModules`,
     confirming the spec's central claim.
   - `mkBaseModule`'s removal of the `hostLocalModules` reference was verified at the
     source level (the `imports` expression literally reads
     `roles.${role}.baseModules ++ roles.${role}.extraModules`, with no
     `hostLocalModules` term) rather than via a synthetic runtime test — the absence of
     a reference is a static fact provable by direct inspection, not something that
     needs dynamic proof (unlike H-18's overlay-count test, which was verifying a
     *positive* runtime behavior change).
   - `git ls-files hardware-configuration.nix` — empty. ✓
   - `system.stateVersion` — untouched. ✓
   - `flake.nix` inputs (`url =`/`follows` lines) — untouched via `git diff`. ✓
   - `bash scripts/preflight.sh` — exit 0, PASSED. Same pre-existing WARNs as every
     prior review this session; nothing new.

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
