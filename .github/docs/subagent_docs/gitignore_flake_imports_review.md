# Review: Stop gitignoring flake-imported files in /etc/nixos

Spec: `.github/docs/subagent_docs/gitignore_flake_imports_spec.md`

## Files Reviewed
- `scripts/stateless-setup.sh` (.gitignore heredoc)
- `scripts/install.sh` (.gitignore heredoc, repair loop, kernel-override
  tracking on write and on abort cleanup)

## Findings

1. **Specification Compliance** — All four change sites implemented as
   specified; both heredocs now list only `secrets/`, `*.bak`,
   `vexos-variant`.
2. **Best Practices** — `git add -f` is the standard way to track a file a
   stale committed `.gitignore` still lists (gitignore only affects untracked
   files; once tracked, fetchGit/git+file includes it). Repair loop guards
   each add with `[ -f … ]`. Abort path pairs `rm -f` with
   `git rm -q --cached … || true` so a staged-then-deleted override cannot
   linger in the index.
3. **Consistency** — Both scripts keep the same `.gitignore` content; the
   `$GIT` bootstrap variable (defined earlier in install.sh) is reused for
   all new git calls, all of which occur after its definition.
4. **Maintainability** — Comments at each site explain the git+file
   tracked-files-only constraint.
5. **Completeness** — Covers: fresh stateless install (reported failure),
   fresh installs of all other roles (same unconditional import), repair of
   repos created by older installer versions, stateless user override
   (locked-account hazard), and the kernel cache-miss fallback (previously
   inoperative because the override never entered the flake source).
6. **Performance** — Negligible (a few git calls).
7. **Security** — No regression: the password hash in
   stateless-user-override.nix is already embedded in the system closure in
   /nix/store by the build; hardware-configuration.nix and the kernel
   override contain no secrets; `secrets/` remains untracked.
8. **API Currency** — No external libraries; Context7 not applicable.
9. **Build Validation**
   - `bash -n` passes on both scripts.
   - No `.nix` files modified — flake structure, `system.stateVersion`,
     flake inputs, and the repo-level hardware-configuration.nix exclusion
     are untouched (full preflight in Phase 6).
   - Empirical fetchGit scratch test was denied by the sandbox; correctness
     rests on documented git/fetchGit semantics plus the user's install log,
     which demonstrates the exclusion of ignored files (the failing import).

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

## Result: PASS
