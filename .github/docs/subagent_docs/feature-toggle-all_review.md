# enable-feature/disable-feature "all" — Review

## Spec Compliance

Matches spec exactly: `all` special-case added to both recipes, reusing the existing
per-feature recipe body via recursive `just` invocation rather than duplicating logic.

## Best Practices / Consistency

- No new recipe names — `all` is handled as a value of the existing `feature`
  parameter, consistent with how the recipes already work (single positional arg).
- Reuses `_feature_names` as the single source of truth for the feature list — adding a
  5th feature in the future requires no change to the `all` logic.
- No duplication of the sed-toggle logic, template bootstrap, or per-feature
  "what this adds" messaging — each call to `just enable-feature "$f"` / `just
  disable-feature "$f"` runs the exact same code path a manual single-feature
  invocation would.

## Completeness

Both directions implemented (`enable-feature all`, `disable-feature all`), both usage
comments updated.

## Security

No secrets, no new file permissions, no new sudo usage beyond what the existing
per-feature recipes already do.

## Performance

Four sequential `just` subprocess invocations instead of one — negligible (each is a
few `sed`/`grep` calls).

## Build Validation

This is a `justfile`-only change; no `.nix` files touched, so there is no evaluation
impact. Verified anyway per the standing checklist:

| Check | Result |
|---|---|
| `just --list` | PASS — both recipes listed with updated usage comments |
| `just --dry-run enable-feature all` | PASS — expands to a loop over `gaming development print3d virtualization`, each calling `just enable-feature "$f"` |
| `just --dry-run disable-feature all` | PASS — same, calling `disable-feature` |
| `just --dry-run enable-feature bogus` | PASS — unknown-feature error path unaffected, confirms no regression |
| `nix flake show --impure` | PASS — unaffected, all 30 `nixosConfigurations` + modules evaluate |
| `bash scripts/preflight.sh` | PASS — exit code 0 |

Full end-to-end execution against a real `/etc/nixos/features.nix` could not be run in
this sandbox (no root), same limitation as the prior change in this session.

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 95% | A (dry-run/static verification only, no root to execute live) |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 100% | A |

**Overall Grade: A (99%)**

## Result: PASS
