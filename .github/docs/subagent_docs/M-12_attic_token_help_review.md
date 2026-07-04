# M-12 — Review & Quality Assurance

Status: Phase 3 (Review)
Spec: `.github/docs/subagent_docs/M-12_attic_token_help_spec.md`

## Modified Files

- `justfile` — the `attic)` case in the post-enable info block: fixed the env var
  name (`HS256` → `RS256`) and the secret-generation command
  (`openssl rand -base64 32` → `openssl genrsa -traditional 4096 | base64 -w0`) to
  match `modules/server/attic.nix`'s own correct documentation.

## Review Findings

1. **Specification Compliance** — matches the MASTER_PLAN's exact wording for both
   replacements.
2. **Best Practices** — now consistent with the two other places in this codebase
   that already correctly reference RS256 (`attic.nix`'s header comment,
   `secrets-sops.nix`'s `attic-server-token-rs256-secret-base64` secret name).
3. **Consistency** — text-only fix in a `justfile` help block; no code path changed.
4. **Maintainability** — removes the only remaining `HS256` reference in the repo,
   eliminating a genuine trap (following the old instructions would generate a
   symmetric secret in the wrong format entirely, which `atticd` would reject at
   startup).
5. **Completeness** — repo-wide grep after the fix confirms zero `HS256` references
   remain.
6. **Performance** — n/a.
7. **Security** — n/a; no secret material involved, just corrected user guidance.
8. **API Currency** — n/a.
9. **Build Validation:**
   - `just --list` — parses without error.
   - Repo-wide grep for `RS256`/`HS256` confirms only the corrected line remains and
     no stale `HS256` reference is left anywhere.
   - No Nix module touched by this change — Nix-focused build validation steps don't
     apply (same as M-11).
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
| Build Success | 100%* | A |

*No Nix build surface affected by this change.

**Overall Grade: A (100%)**

## Returns

- Build result: PASS
- **PASS**
