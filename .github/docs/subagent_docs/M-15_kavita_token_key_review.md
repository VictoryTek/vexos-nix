# M-15 — Review & Quality Assurance

Status: Phase 3 (Review)
Spec: `.github/docs/subagent_docs/M-15_kavita_token_key_spec.md`

## Modified Files

- `modules/server/kavita.nix` — added `system.activationScripts.kavitaTokenKey`,
  auto-generating `/var/lib/kavita/token-key` (64 random bytes, base64-encoded, no
  trailing newline) idempotently on first activation, matching the pattern already
  established for VexBoard's secret (H-15).

## Review Findings

1. **Specification Compliance** — matches the spec exactly.
2. **Best Practices** — auto-generating a purely-internal secret that no human ever
   needs to type/remember is the correct approach here (as opposed to requiring manual
   creation or a `just enable` prompt, which makes sense for something like a login
   password but not a JWT signing key).
3. **Consistency** — mirrors `modules/server/vexboard.nix`'s activation-script pattern
   exactly (idempotent existence check, `mkdir -p` the containing directory itself
   rather than depending on tmpfiles ordering, `chmod 0600`).
4. **Maintainability** — the comment explains both *why* auto-generation is
   appropriate here (unlike a password) and *what breaks* without it (permanent crash
   loop via `LoadCredential=`).
5. **Completeness** — the cited defect (crash loop from a missing manually-required
   file) is fully resolved.
6. **Performance** — negligible; one existence check per activation.
7. **Security** — the generated key is 64 random bytes (512 bits), matching the
   upstream module's own documented minimum; written `chmod 0600`, root-owned, which is
   sufficient since `LoadCredential=` is processed by the service manager (root) before
   the kavita user is ever involved.
8. **API Currency** — verified `tokenKeyFile`'s exact semantics
   (`type = path`, `LoadCredential=`, mandatory, no default) directly against the
   pinned nixpkgs revision. Noted but did not touch an unrelated, pre-existing
   deprecation (`services.kavita.port` → `settings.Port`) surfaced during evaluation —
   out of scope for this fix, flagged per Surgical Changes rather than silently bundled
   in.
9. **Build Validation:**
   - Forced-branch test (`vexos.server.kavita.enable = true`, plus the
     `networking.hostId` CI-fixture override from M-13 to isolate this test from that
     unrelated assertion): confirmed the full `toplevel` builds, `LoadCredential`
     correctly references the token file path, and the activation script's rendered
     text is exactly as expected.
   - Isolated functional test of the activation script logic itself: confirmed the
     generated key is exactly 64 bytes (88 base64 chars, matching `ceil(64/3)*4`),
     `chmod 0600` permissions, and — critically — idempotency: running the script
     twice does **not** regenerate/overwrite an existing key (verified by comparing
     content before/after a second run).
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
