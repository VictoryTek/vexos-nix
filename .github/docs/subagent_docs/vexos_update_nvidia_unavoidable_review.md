# Review: vexos-update — reclassify unfree NVIDIA userspace + patched openrazer as unavoidable

## Changes reviewed

| File | Change |
|---|---|
| `modules/nix.nix` | kernel-override-clear block: `HEAVY_BUILD_REGEX` → `KERNEL_BLOCK_REGEX` (kernel modules only). Main update block: split single regex into `HEAVY_BUILD_REGEX` (kernel modules, block) + `UNAVOIDABLE_REGEX` (unfree NVIDIA + patched openrazer, proceed). Added `UNAVOIDABLE_BUILDS` partition + informational `VEXOS_LOCAL_BUILD:` output. Updated `VEXOS_CACHE_BLOCK:` message to remove NVIDIA reference. Updated inline comment to document three-way classification. Strict mode updated to clear `UNAVOIDABLE_BUILDS`. |

## Verification

- `nix eval --impure path:#vexos-desktop-amd` → `/nix/store/aydfrh8vwimpg2kz74p2ryyv0igz17id-nixos-system-vexos-25.11.drv` (exit 0)
- `nix eval --impure path:#vexos-desktop-nvidia` → `/nix/store/863j5lmb4144cm37p8qlqchgkz7s99ab-nixos-system-vexos-25.11.drv` (exit 0)
- `nix eval --impure path:#vexos-desktop-vm` → `/nix/store/sh07hxhx7xr84c826mqszfhgxb02q0yk-nixos-system-vexos-25.11.drv` (exit 0)
- `bash scripts/preflight.sh` → **PASSED** (7/7, warnings pre-existing)
- Preflight dry-build shows:
  - `nvidia-open-7.0.11-580.142` → **will be fetched** (cached ✓)
  - `linux-7.0.11-modules` → **will be fetched** (cached ✓)
  - `openrazer-3.10.3-7.0.11.drv` → **will be built** (expected, patched overlay)
  - `vexos-update.drv` → **will be built** (updated script is in closure)
- `hardware-configuration.nix` not tracked ✓
- `system.stateVersion` unchanged in all 6 configuration files ✓

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
| Build Success | 100% | A |

**Overall Grade: A (100%)**

## Result: PASS
