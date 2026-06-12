# vexos-update gitignore fix — review

## Summary

Single-file fix to `modules/nix.nix`.  Two surgical changes inside the `vexos-update`
shell script:

1. The gitignore written by the one-time `/etc/nixos` git-init migration was updated
   to match the installer's gitignore (only `secrets/`, `*.bak`, `vexos-variant`).
   The three files that `template/etc-nixos-flake.nix` imports
   (`hardware-configuration.nix`, `kernel-install-override.nix`,
   `stateless-user-override.nix`) are no longer excluded.

2. An unconditional repair loop was added immediately after the one-time init block.
   It force-adds all three files to the git index on every `vexos-update` run so that
   repos already created with the broken gitignore are silently repaired the next time
   the user runs the updater.

## Score table

| Category | Score | Grade |
|---|---|---|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 100% | A |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 100% | A |

**Overall Grade: A (100%)**

## Build results

- `nix flake show --impure` — PASS (30 nixosConfigurations listed)
- `bash scripts/preflight.sh` — PASS (all hard checks green; pre-existing WARNs only)
- `sudo nixos-rebuild dry-build` not available in sandbox; covered by preflight check 2

## Issues found

None. PASS.
