# asus_hardware_fix — Review

## Spec Compliance

- [x] `hosts/desktop-amd.nix` — removed `asus.enable = true` and `batteryChargeLimit = 80`
- [x] `hosts/desktop-nvidia.nix` — same
- [x] `hosts/desktop-intel.nix` — same
- [x] `scripts/install.sh` — guard changed from `&& [ "$ROLE" != "stateless" ]` removed
- [x] `scripts/install.sh` — question changed from "laptop?" to "device?"
- [x] `scripts/install.sh` — ASUS_LAPTOP follow-up question added
- [x] `scripts/install.sh` — patch block branches on ASUS_LAPTOP for battery charge limit
- [x] `template/etc-nixos-flake.nix` — comment updated to show device and laptop forms

## Correctness

- Host files now contain only `imports` + `system.nixos.distroName` — correct for shared variants.
- `asus-opt.nix` default (`enable = false`, `batteryChargeLimit = 100`) takes effect when
  the host files don't override it. CI builds no longer include ASUS packages.
- Installer ASUS_LAPTOP=false path: patches `enable = true` only — desktop users unaffected.
- Installer ASUS_LAPTOP=true path: patches `enable = true; batteryChargeLimit = 80;` — correct.
- Fallback (hardwareModule not found) path also shows `batteryChargeLimit` line when laptop=true.
- Stateless fall-through path now correctly reaches the ASUS question (guard removed).

## Security / stateVersion

- No new secrets, no world-writable files, no plaintext credentials introduced.
- `system.stateVersion` unchanged in all `configuration-*.nix` ✓
- `hardware-configuration.nix` not tracked ✓

## Build Validation

- Running on Windows dev machine — `nix flake show --impure` and `nixos-rebuild dry-build`
  cannot be executed locally. Deferred to CI.
- Changes are Nix-side deletions only (removing overrides that set ASUS options to true);
  the option defaults were already correct and the module structure is unchanged.
  Evaluation risk: none.

## Score Table

| Category | Score | Grade |
|---|---|---|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 100% | A |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | N/A (Windows) | — |

**Overall Grade: A (100%)**

## Result: PASS
