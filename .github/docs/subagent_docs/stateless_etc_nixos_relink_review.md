# Stateless /etc/nixos relink — Review

Phase 3 review of `stateless_etc_nixos_relink_spec.md`. Modified: `modules/impermanence.nix`.

## Specification compliance
- The activation script is generated from one list (`justfile`, `just`, `scripts`,
  `template/server-services.nix`, `template/features.nix`). Each target is taken from
  `config.environment.etc."nixos/<name>".source`, so it cannot drift from
  `modules/packages-common.nix`.
- The per-entry guard is unchanged in spirit: a real file or directory is left alone; a missing
  entry or symlink is (re)pointed; parent directories are created.
- No new options and no role `mkIf`; the block stays inside the module's own `mkIf cfg.enable`.

## Testing
- Evaluated `vexos-stateless-amd` activation text: all 5 entries link to the exact
  store paths `environment.etc` uses.
- The generated script was run against a temp persistent dir:
  1. Fresh: all 5 linked, and `scripts/upgrade-wrapper.sh` is reachable.
  2. Re-run: unchanged (idempotent).
  3. Stale symlink → repointed; a real `justfile` file and a real `just/` dir → untouched.

## Build validation
| Check | Result |
|---|---|
| eval desktop-amd / -nvidia / -vm | PASS |
| eval stateless-amd / stateless-nvidia / htpc-amd | PASS |
| `scripts/preflight.sh` | PASS (exit 0) |
| `sudo nixos-rebuild dry-build` | not runnable here (no non-interactive sudo) |

## Notes
- Not verified on a live stateless host. The bug itself is derived from the code
  (the bind mount hides `environment.etc` links, as the existing justfile relink
  already documented).
- `configuration-stateless.nix:83-85` claimed the justfile needed "no stateless-specific
  handling", which was inaccurate even before this change. Corrected at the user's request
  to point at the relink in `modules/impermanence.nix` (comment only; stateless still
  evaluates and preflight still passes).

## Scores

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A+ |
| Best Practices | 95% | A |
| Functionality | 95% | A |
| Code Quality | 96% | A |
| Security | 100% | A+ |
| Performance | 100% | A+ |
| Consistency | 98% | A+ |
| Build Success | 100% | A+ |

**Overall Grade: A+ (98%)**

**Result: PASS**
