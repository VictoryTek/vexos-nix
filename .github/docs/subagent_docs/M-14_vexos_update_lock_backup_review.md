# M-14 — Review & Quality Assurance

Status: Phase 3 (Review)
Spec: `.github/docs/subagent_docs/M-14_vexos_update_lock_backup_spec.md`

## Modified Files

- `modules/nix.nix` (`vexos-update` script) — moved `rm -f
  /etc/nixos/flake.lock.bak` to after a successful `nixos-rebuild switch` instead of
  immediately before it; both `nixos-rebuild dry-build` call sites now detect their own
  failure (via `if ! VAR=$(cmd 2>&1); then ...`) instead of swallowing it with
  `|| true`, printing the dry-build output and restoring/removing the lock backup as
  appropriate before exiting 1.

## Review Findings

1. **Specification Compliance** — all three changes from the spec implemented exactly.
2. **Best Practices** — the `if ! VAR=$(cmd); then` pattern correctly captures command
   output regardless of exit status while still reacting to failure, under
   `set -euo pipefail` — the same pattern already established for `vexos-notify`'s
   `register()` helper earlier in this session (H-17), kept consistent here.
3. **Consistency** — the main dry-build failure path (restore lock, remove backup,
   exit 1) mirrors the structure of the existing "heavy build" block a few lines later,
   which does the same restore-and-exit for a different reason.
4. **Maintainability** — error messages at both dry-build sites explain what failed and
   why (kernel-cache-check vs. post-flake-update), making a real failure immediately
   actionable in the journal/build log instead of silently falling through.
5. **Completeness** — both dry-build call sites and the backup-deletion timing are all
   fixed; no partial fix.
6. **Performance** — no change.
7. **Security** — this is itself a resilience/data-integrity fix: a failed update no
   longer destroys the one artifact (the lock backup) that would let a user recover.
8. **API Currency** — n/a, standard bash/nix CLI usage.
9. **Build Validation:**
   - Built the actual `vexos-update` derivation and ran `bash -n` (syntax OK) and
     `shellcheck` against the *rendered* script — zero findings at all (not even a
     pre-existing unrelated one this time).
   - Functional test of the core claim: an isolated bash simulation reproducing the
     exact "backup, apply, then delete backup" structure with a failing "apply" step
     (`false`) under `set -euo pipefail` — confirmed the script aborts before reaching
     the `rm -f` line and the backup file survives on disk. This directly demonstrates
     the fix's central behavior rather than relying on reasoning about `set -e`
     semantics alone.
   - `nix flake show --impure` — passed.
   - Required targets (`vexos-desktop-amd`, `-nvidia`, `-vm`) evaluated cleanly;
     `modules/nix.nix` is a universal base module, so this exercises the same code path
     used by every role.
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
