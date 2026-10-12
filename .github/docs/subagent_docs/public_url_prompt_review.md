# Review — public-URL prompt / `just service set-url`

Spec: `public_url_prompt_spec.md`. Files: `just/lib.sh`, `just/server-enable.just`, `just/server.just`.

## Checks run
- Helper behaviour (pty harness, WSL): Enter keeps default and writes nothing; missing scheme re-asks;
  trailing slashes stripped; `"`, `${...}`, spaces rejected; already-set value shown and only replaced on `y`
  (trailing comment preserved, single line); port override shown in the default; vaultwarden re-asks on empty;
  non-service returns 1; no terminal skips with a hint.
- `scripts/preflight.sh` (all 12 stages, WSL): exit 0 — `just` parses (97 recipes), shellcheck -S warning clean
  over 58 recipes + `just/lib.sh`, service tables agree, dry-build `.#vexos-desktop-amd` passed.
- No Nix modules changed, so no other variants were evaluated; option defaults untouched.
- `scripts/migrate-services.sh` does not exist; no other script writes these options.

## Findings
- No CRITICAL issues.
- Deviation from the request, deliberate: vaultwarden/headscale have an invalid placeholder default guarded
  by a build assertion, so they require an answer instead of "Enter keeps default".
- Non-tty runs skip the prompt rather than refuse, so VexPortal-driven enable is unchanged.

## Score
| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 95% | A |
| Best Practices | 95% | A |
| Functionality | 95% | A |
| Code Quality | 93% | A |
| Security | 95% | A |
| Performance | 100% | A |
| Consistency | 95% | A |
| Build Success | 100% | A |

**Overall Grade: A (96%) — PASS**
