# M-16 — Review & Quality Assurance

Status: Phase 3 (Review)
Spec: `.github/docs/subagent_docs/M-16_enable_sed_anchor_spec.md`

This pass also includes a small out-of-scope cleanup requested directly by the user:
fixing the `services.kavita.port` deprecation warning noticed during the M-15 review
(`modules/server/kavita.nix`), unrelated to M-16 itself but bundled in at the user's
explicit request.

## Modified Files

- `justfile` — anchored all 4 `sed -i "s|}|...` call sites (the `enable-feature`
  recipe, the `enable` service recipe, and both VexBoard auto-secret/auto-enable
  insertions) to `"\$ s|^}|...` — only the file's actual final line, only if it starts
  with `}`.
- `modules/server/kavita.nix` — `port = 5000;` → `settings.Port = 5000;` (current,
  non-deprecated option path).

## Review Findings

1. **Specification Compliance** — all 4 call sites fixed identically, matching the
   spec's decision to fix all of them (not just the one MASTER_PLAN named) since they
   share the identical defect shape.
2. **Best Practices** — anchoring to `$` (last line) + `^}` (line starts with the
   brace) is the minimal, correct fix — doesn't require restructuring the insertion
   logic itself, just targeting it precisely.
3. **Consistency** — all four sites now use the identical anchored pattern.
4. **Maintainability** — added an inline comment at the `enable` recipe's site
   explaining *why* the anchor matters (a nested `}` earlier in the file).
5. **Completeness** — repo-wide grep confirmed exactly 4 occurrences of the fragile
   pattern before the fix; all 4 addressed, none missed.
6. **Performance** — n/a.
7. **Security** — n/a; this is a data-integrity fix (prevents config file corruption),
   not security-relevant.
8. **API Currency** — the kavita fix directly resolves a deprecation flagged by the
   current nixpkgs revision itself.
9. **Build Validation:**
   - Direct reproduction of the bug: built a synthetic `server-services.nix` with a
     nested `{ ... }` on one line (a realistic shape — an inline settings attrset) and
     ran both the **old** and **new** sed patterns against copies of it. The old
     pattern visibly corrupted the file — inserted the new option *inside* the nested
     block and also appended a duplicate at the end. The new pattern inserted it once,
     correctly, before the real closing brace.
   - Regression check: ran the new pattern against a plain (no-nesting) file — the
     common, everyday case — and confirmed it still inserts correctly there too.
   - `just --list` — parses without error.
   - Kavita fix: evaluated `services.kavita.settings.Port` on a forced-branch build
     and confirmed it resolves to 5000 with no deprecation warning, and the resulting
     `.drv` hash is unchanged from before the fix (confirms this is purely a spelling
     correction with zero behavioral change).
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
