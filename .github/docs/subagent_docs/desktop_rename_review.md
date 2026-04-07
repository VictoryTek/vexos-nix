# Review: Desktop Rename (`vexos-{gpu}` → `vexos-desktop-{gpu}`)

**Date:** 2026-04-06  
**Reviewer:** Review Subagent  
**Spec:** `.github/docs/subagent_docs/desktop_rename_spec.md`  

---

## 1. Files Reviewed

| # | File | Status |
|---|------|--------|
| 1 | `flake.nix` | ✅ All four `nixosConfigurations` renamed to `vexos-desktop-{amd,nvidia,vm,intel}`. Comments updated. |
| 2 | `hosts/amd.nix` | ✅ Comment updated to `.#vexos-desktop-amd` |
| 3 | `hosts/nvidia.nix` | ✅ Comment updated to `.#vexos-desktop-nvidia` |
| 4 | `hosts/intel.nix` | ✅ Comment updated to `.#vexos-desktop-intel` |
| 5 | `hosts/vm.nix` | ✅ Comment updated to `.#vexos-desktop-vm`; `networking.hostName` changed to `"vexos-desktop-vm"` |
| 6 | `configuration.nix` | ✅ `networking.hostName` default changed to `"vexos-desktop"` via `lib.mkDefault` |
| 7 | `scripts/preflight.sh` | ✅ Both `for TARGET` loops updated to use `vexos-desktop-{amd,nvidia,vm,intel}` |
| 8 | `template/etc-nixos-flake.nix` | ✅ All comments and `nixosConfigurations` attributes use new names |
| 9 | `README.md` | ✅ All variant names, commands, and table entries use `vexos-desktop-*` |
| 10 | `.github/copilot-instructions.md` | ✅ Build/test commands, constraints, and output descriptions updated to `vexos-desktop-*`; now lists all four outputs including `vexos-desktop-intel` |

---

## 2. Stale Reference Scan

Searched the entire workspace for old names (`vexos-amd`, `vexos-nvidia`, `vexos-intel`, `vexos-vm`) and the regex pattern `.#vexos-{word}` without `desktop-`.

**Result:** All matches are exclusively in `.github/docs/subagent_docs/` (historical spec/review documents). **Zero stale references** found in any active code, configuration, script, template, or documentation file.

---

## 3. Constraint Verification

| Constraint | Status | Detail |
|------------|--------|--------|
| `system.stateVersion` not changed | ✅ PASS | `system.stateVersion = "25.11"` present in `configuration.nix` — unchanged |
| `nixosModules` attributes not renamed | ✅ PASS | Attributes remain `base`, `gpuAmd`, `gpuNvidia`, `gpuVm`, `gpuIntel`, `asus` — untouched |
| `hardware-configuration.nix` not in repo | ✅ PASS | No such file found in the repository |
| `nixpkgs.follows` maintained | ✅ PASS | All inputs (`nix-gaming`, `home-manager`, `up`) declare `inputs.nixpkgs.follows = "nixpkgs"` |

---

## 4. Build Validation

All builds used `nix build --dry-run --impure` (equivalent to `nixos-rebuild dry-build` without requiring `sudo`).

| Variant | Command | Exit Code | Result |
|---------|---------|-----------|--------|
| AMD | `nix build --dry-run --impure .#nixosConfigurations.vexos-desktop-amd.config.system.build.toplevel` | 0 | ✅ PASS |
| NVIDIA | `nix build --dry-run --impure .#nixosConfigurations.vexos-desktop-nvidia.config.system.build.toplevel` | 0 | ✅ PASS |
| VM | `nix build --dry-run --impure .#nixosConfigurations.vexos-desktop-vm.config.system.build.toplevel` | 0 | ✅ PASS |
| Intel | `nix build --dry-run --impure .#nixosConfigurations.vexos-desktop-intel.config.system.build.toplevel` | 0 | ✅ PASS |
| Flake check | `nix flake check --impure` | 0 | ✅ PASS |

---

## 5. Issues Found

**None.** The rename is comprehensive, consistent, and introduces no regressions.

---

## 6. Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A+ |
| Best Practices | 100% | A+ |
| Functionality | 100% | A+ |
| Code Quality | 100% | A+ |
| Security | 100% | A+ |
| Performance | 100% | A+ |
| Consistency | 100% | A+ |
| Build Success | 100% | A+ |

**Overall Grade: A+ (100%)**

---

## 7. Verdict

### **PASS**

The desktop rename is a clean, mechanical find-and-replace across all 10 files. Every `nixosConfigurations` attribute, host comment, rebuild command, preflight target, template output, README reference, and copilot-instructions entry uses the new `vexos-desktop-{gpu}` naming consistently. The `nixosModules` API surface was correctly left unchanged. All four system closures evaluate successfully. No stale references remain in active files.
