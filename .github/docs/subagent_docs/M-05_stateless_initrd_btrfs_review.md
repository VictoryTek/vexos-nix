# M-05 — Review & Quality Assurance

Status: Phase 3 (Review)
Spec: `.github/docs/subagent_docs/M-05_stateless_initrd_btrfs_spec.md`

## Modified Files

- `modules/stateless-disk.nix` — `boot.initrd.kernelModules = lib.mkDefault [ "btrfs" ];`
  → plain `[ "btrfs" ];`, with an expanded comment explaining the list-merge-vs-priority
  mechanics.

## Review Findings

1. **Specification Compliance** — exact one-line fix as proposed.
2. **Best Practices** — correctly identifies that this option needs merge (not
   override) semantics and drops `mkDefault` deliberately rather than reaching for a
   more complex workaround.
3. **Consistency** — single-line change within an already role-scoped module; no
   shared/base module touched.
4. **Maintainability** — the expanded comment documents the *mechanism* (list options
   only merge definitions at the single highest-priority tier) so a future reader
   doesn't have to rediscover why `mkDefault` was wrong here.
5. **Completeness** — the one cited line is fixed.
6. **Performance** — no change.
7. **Security** — no change.
8. **API Currency** — n/a, core NixOS module-system semantics, not an external API.
9. **Build Validation:**
   - Synthetic test #1: built a `nixosSystem` combining this module with a stub
     `hardware-configuration.nix` declaring a **non-empty**
     `boot.initrd.kernelModules = [ "nvme" ]` — confirmed the final merged list is
     `[ "btrfs" "dm_mod" "nvme" ]` (both present), proving concatenation.
   - Synthetic test #2 — the actual bug scenario: same setup but with an **empty**
     `boot.initrd.kernelModules = [ ]` (the common real-world case for
     `nixos-generate-config`) — confirmed the final list is `[ "btrfs" "dm_mod" ]`.
     Under the old `mkDefault` code, this exact scenario would have discarded `btrfs`
     entirely; this test directly demonstrates the fix closes that gap.
   - `nix flake show --impure` — passed.
   - Required targets (`vexos-desktop-amd`, `-nvidia`, `-vm`) evaluated cleanly;
     `vexos-stateless-amd` (the affected role, per Phase 3's conditional rule) also
     evaluated cleanly. Its `.drv` hash changed from the pre-fix baseline — expected
     and correct, since this fix genuinely changes the merged `kernelModules` list for
     real stateless builds (unlike M-03/M-04, which only affected opt-in services).
   - `git ls-files hardware-configuration.nix` — empty. ✓
   - `system.stateVersion` — untouched. ✓
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
