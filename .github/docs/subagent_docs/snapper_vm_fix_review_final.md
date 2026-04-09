# Review: snapper-boot VM Fix — Final Review

**Date:** 2026-04-09
**Reviewer:** Review Agent
**Scope:** Move `vexos.btrfs.enable = false` and `vexos.swap.enable = false` from `hosts/vm.nix` into `modules/gpu/vm.nix` so both the repo build path and the external `/etc/nixos/flake.nix` template path are covered.

---

## Validation Checklist Results

| # | Check | Result |
|---|-------|--------|
| 1 | `modules/gpu/vm.nix` contains `vexos.btrfs.enable = false;` | ✅ PASS (line 29) |
| 2 | `modules/gpu/vm.nix` contains `vexos.swap.enable = false;` | ✅ PASS (line 32) |
| 3 | `hosts/vm.nix` no longer sets these options (replaced with comment) | ✅ PASS — comment explains rationale |
| 4 | `vexos.btrfs.enable` option is defined in `modules/system.nix` | ✅ PASS — defined with `lib.mkOption` at top of file |
| 5 | `vexos.swap.enable` option is defined in `modules/system.nix` | ✅ PASS — defined with `lib.mkOption` at top of file |
| 6 | `nixosModules.gpuVm` in `flake.nix` imports `modules/gpu/vm.nix` | ✅ PASS — `gpuVm = { ... }: { imports = [ ./modules/gpu/vm.nix ]; ... }` |
| 7 | `hosts/vm.nix` also imports `modules/gpu/vm.nix` | ✅ PASS — `imports = [ ../configuration.nix ../modules/gpu/vm.nix ]` |
| 8 | AMD, NVIDIA, Intel GPU modules do NOT contain `vexos.btrfs` or `vexos.swap` overrides | ✅ PASS — grep confirms zero matches in those files |
| 9 | `hardware-configuration.nix` is NOT tracked in the repo | ✅ PASS — `file_search` returned no results; `flake.nix` references `/etc/nixos/hardware-configuration.nix` as an absolute path |
| 10 | `system.stateVersion` has not been changed | ✅ PASS — `configuration.nix` line 123: `system.stateVersion = "25.11";` |

---

## Import Chain Verification

### Repo build path

```
flake.nix: nixosConfigurations.vexos-desktop-vm
  └── commonModules ++ [ ./hosts/vm.nix ]
        └── hosts/vm.nix
              └── imports: [ ../configuration.nix  ../modules/gpu/vm.nix ]
                    └── modules/gpu/vm.nix
                          ├── vexos.btrfs.enable = false  ✅
                          └── vexos.swap.enable  = false  ✅
```

### External template path

```
/etc/nixos/flake.nix (template/etc-nixos-flake.nix)
  └── mkVariant "vexos-desktop-vm" vexos-nix.nixosModules.gpuVm
        └── vexos-nix.nixosModules.gpuVm
              └── imports: [ ./modules/gpu/vm.nix ]
                    └── modules/gpu/vm.nix
                          ├── vexos.btrfs.enable = false  ✅
                          └── vexos.swap.enable  = false  ✅
```

Both paths converge on `modules/gpu/vm.nix`. The fix is correctly placed.

---

## Analysis

### Root cause addressed

The original failure (`snapper-boot.service: Creating snapshot failed`) occurred because the VM btrfs layout is not snapper-compatible. The previous fix placed the disable flags in `hosts/vm.nix`, which is only used by the repo build path. The external template path uses `nixosModules.gpuVm`, which bypasses `hosts/vm.nix` entirely and goes directly to `modules/gpu/vm.nix`. Moving the flags into `modules/gpu/vm.nix` closes this gap.

### Comment quality in hosts/vm.nix

The replacement comment in `hosts/vm.nix` is clear and accurate:

```nix
# vexos.btrfs.enable = false and vexos.swap.enable = false are set in
# modules/gpu/vm.nix so they apply to both repo builds and the external
# /etc/nixos/flake.nix template that consumes nixosModules.gpuVm.
```

This correctly documents _why_ the options were moved, preventing future regression.

### Option availability at evaluation time

`modules/system.nix` defines both options unconditionally in its `options` block. Since `configuration.nix` imports `modules/system.nix` (and both repo and template paths include `configuration.nix` or `nixosModules.base` which wraps it), the options are guaranteed to be in scope when `modules/gpu/vm.nix` is evaluated. No circular dependency or undefined attribute risk exists.

### No scope creep

`amd.nix`, `nvidia.nix`, and `intel.nix` contain no `vexos.btrfs` or `vexos.swap` mutations. The fix is precisely scoped to the VM module.

### `lib.mkForce` not required

The btrfs auto-detect default in `system.nix` is `false` when `fileSystems["/"].fsType != "btrfs"`. In a VM that is provisioned on ext4 or a non-btrfs volume, the default would already be `false`. Setting it explicitly to `false` is **still correct and defensive** — it guarantees the behaviour regardless of the guest's filesystem layout (e.g., a VM provisioned on btrfs storage). `lib.mkForce` is not needed because no other module forces it `true`.

---

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 98% | A |
| Functionality | 100% | A |
| Code Quality | 98% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | N/A (dry-build not available in review agent) | — |

**Overall Grade: A (99%)**

> Build Success is marked N/A because a live `nixos-rebuild dry-build` cannot be executed in the review environment. All static analysis checks pass. A preflight run (`scripts/preflight.sh`) should be executed before pushing.

---

## Summary

The fix is **correct, minimal, and well-reasoned**. The root cause was that `vexos.btrfs.enable = false` was placed in `hosts/vm.nix`, which is not on the code path taken by the external `/etc/nixos/flake.nix` template. Moving both disable flags into `modules/gpu/vm.nix` ensures they are enforced unconditionally for every consumer of the VM GPU module — both the repo's own `nixosConfigurations.vexos-desktop-vm` and the external `nixosModules.gpuVm`. No other modules are affected; `system.stateVersion` is unchanged; `hardware-configuration.nix` is not tracked.

---

## Verdict

**APPROVED**
