# M-17 — Review & Quality Assurance

Status: Phase 3 (Review)
Spec: `.github/docs/subagent_docs/M-17_homepage_allowed_hosts_spec.md`

## Modified Files

- `modules/server/homepage.nix` — added `vexos.server.homepage.allowedHosts` option
  (default `"localhost:${cfg.port}"`); wired to
  `virtualisation.oci-containers.containers.homepage.environment.HOMEPAGE_ALLOWED_HOSTS`.

## Review Findings

1. **Specification Compliance** — matches the spec: a configurable option (not a hard
   assertion, since a working default exists) matching this module's existing style.
2. **Best Practices** — the option description explains both *why* it's required
   (Homepage v0.10+ CSRF protection) and the concrete constraint (no wildcard support —
   list every access path).
3. **Consistency** — matches the existing `port` option's style exactly (plain
   `lib.mkOption`, description, no assertion).
4. **Maintainability** — future users hitting the same "every request rejected"
   symptom will find the answer directly in the option description, not just in a
   MASTER_PLAN doc.
5. **Completeness** — the cited defect (missing env var causing 100% request
   rejection) is fully resolved with a working default.
6. **Performance** — no change.
7. **Security** — no regression; `HOMEPAGE_ALLOWED_HOSTS` is itself a CSRF-protection
   mechanism, now correctly wired rather than absent.
8. **API Currency** — the fix directly addresses a documented behavior change in
   Homepage v0.10+ (which this module always tracks via `:latest`).
9. **Build Validation:**
   - Forced-branch test (default, no override): confirmed
     `environment.HOMEPAGE_ALLOWED_HOSTS == "localhost:3010"` and the full toplevel
     builds.
   - Forced-branch test (custom `allowedHosts = "192.168.1.50:3010"`): confirmed the
     override reaches the container's environment correctly.
   - `nix flake show --impure` — passed.
   - Required targets (`vexos-desktop-amd`, `-nvidia`, `-vm`) evaluated cleanly.
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
