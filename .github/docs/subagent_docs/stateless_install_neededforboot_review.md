# Review: Fix stateless install — neededForBoot assertion failure

## Specification Compliance

Both fixes match the spec exactly:
- `stateless-setup.sh`: changed to `--no-filesystems` + manual filesystem block append with UUIDs from partlabels
- `stateless-disk.nix`: added separate `lib.mkForce` definitions for `neededForBoot`

## Best Practices

- Script change mirrors the established pattern in `migrate-to-stateless.sh` — same perl/head pattern, same Nix syntax, same UUID sourcing approach
- Module change uses the correct NixOS pattern: separate attribute-path definitions for priority overrides, not `lib.mkForce` inside `lib.mkDefault`
- `blkid -s UUID -o value` is the canonical way to retrieve UUIDs on Linux
- Partition labels (`disk-main-ESP`, `disk-main-data`) sourced from the disko template — reliable after `udevadm settle`

## Consistency

- Matches Option B module architecture (no new `lib.mkIf` guards in shared modules)
- `neededForBoot` is now consistently enforced via `lib.mkForce` as a separate definition, not buried inside a `lib.mkDefault` block where it can be silently overridden
- Module comment updated to describe both install paths accurately

## Maintainability

- The WHY is documented: comment in `stateless-disk.nix` explains precisely why the separate `lib.mkForce` definition is needed
- Pattern is consistent with `migrate-to-stateless.sh` so maintainers have one model to follow

## Completeness

- Both install paths now produce `hardware-configuration.nix` with `neededForBoot = true`
- The module defensive fix ensures robustness even if a user manually regenerates `hardware-configuration.nix` without the correct entries

## Security

- No secrets introduced
- UUID values from `blkid` are disk identifiers, not credentials
- `TMPFILE` created and used by the current user; sudo only for the final `cp` to `/mnt`

## Performance

- No regressions. `blkid` is a fast one-shot lookup

## Build Validation

- `nix flake show --impure`: PASSED (all outputs listed without errors)
- `nix eval --impure .#nixosConfigurations.vexos-desktop-amd.config.system.build.toplevel.drvPath`: PASSED
- `nix eval --impure .#nixosConfigurations.vexos-desktop-nvidia.config.system.build.toplevel.drvPath`: PASSED
- `nix eval --impure .#nixosConfigurations.vexos-desktop-vm.config.system.build.toplevel.drvPath`: PASSED
- `git ls-files hardware-configuration.nix`: empty (not tracked) ✔
- `system.stateVersion` unchanged in all `configuration-*.nix` ✔
- No new flake inputs ✔
- `sudo nixos-rebuild dry-build` unavailable in sandboxed environment; `nix eval` substituted per CLAUDE.md

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 100% | A |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 95% | A |

**Overall Grade: A (99%)** — 1% docked for inability to run `nixos-rebuild dry-build` in sandboxed env; `nix eval` confirms full evaluation success for all three desktop variants.

## Result: PASS
