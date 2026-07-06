# L-05 — Review & Quality Assurance

Status: Phase 3 (Review)
Spec: `.github/docs/subagent_docs/L-05_gitleaks_output_hidden_spec.md`

## Modified Files

- `scripts/preflight.sh` — gitleaks step: removed `2>/dev/null`, added
  `--verbose`. Flake-structure check: `nix flake show --impure --json` is
  now evaluated once instead of twice, reusing the captured output for
  both the pass/fail test and the `jq` count extraction.

## Review Findings

1. **Specification Compliance** — matches the spec, and goes further than
   the plan's literal ask (which only mentioned removing `2>/dev/null`):
   traced gitleaks' actual source to find that removing the redirect
   alone would still produce no per-finding output, since neither
   `--verbose` nor `--report-path` was ever passed.
2. **Best Practices** — verified against gitleaks' actual Go source
   (`logging/log.go`, `cmd/root.go`, `detect/detect.go`) rather than
   assuming CLI behavior from memory, given this is exactly the kind of
   "complex external tool" case worth checking directly.
3. **Consistency** — the flake-show fix follows the same "capture once,
   reuse" pattern already used elsewhere in this script for other checks.
4. **Maintainability** — a single source of truth for the flake-show JSON
   removes any chance of the exit-code check and the count extraction
   silently disagreeing in the future.
5. **Completeness** — both sub-items in L-05 addressed (gitleaks output
   visibility, duplicate `nix flake show` evaluation).
6. **Performance** — halves the `nix flake show --impure` evaluation cost
   in this check (was 2 full evaluations of the entire flake structure,
   now 1).
7. **Security** — net improvement: a real secret finding will now
   actually be visible to the operator instead of silently reporting
   "review output above" with nothing to review.
8. **API Currency** — n/a, no new dependency; gitleaks' CLI flags used
   here (`--verbose`, `--redact`, `--exit-code`) are all pre-existing,
   stable flags.
9. **Build Validation:**
   - `bash -n scripts/preflight.sh` — syntax OK.
   - **Real end-to-end run without gitleaks installed**: preflight still
     correctly falls back to the "gitleaks not installed" WARN branch —
     confirms the fix doesn't assume gitleaks is present.
   - **Real end-to-end run with gitleaks installed** (`nix shell
     nixpkgs#gitleaks --command bash scripts/preflight.sh`): gitleaks'
     actual scan output is now visible in the terminal — "934 commits
     scanned", "scanned ~9.26 MB", "no leaks found" — none of which
     printed before this fix (all silently discarded by `2>/dev/null`).
   - **Source-level verification of `--verbose`'s effect**: read
     `detect/detect.go:744-746` directly — `printFinding(finding,
     d.NoColor)` is called precisely `if d.Verbose`, confirming a real
     finding would now print (redacted secret, file, line, rule) rather
     than only affecting log-level noise. (A live synthetic-secret test
     was attempted but gitleaks' default ruleset/allowlist heuristics
     made it non-trivial to craft a fixture that reliably triggers
     without deeper rule-by-rule tuning — the source-level confirmation
     was judged more reliable than fighting entropy/allowlist heuristics
     to force a synthetic match.)
   - `nix flake show --impure` — passed; confirmed the preflight's own
     flake-structure check now reports "30 nixosConfigurations listed"
     (correct count) from a single evaluation.
   - `git ls-files hardware-configuration.nix` — empty. ✓
   - `bash scripts/preflight.sh` — exit 0, PASSED (both with and without
     gitleaks on `PATH`). Same pre-existing WARNs as every prior review
     this session — nothing new.

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
