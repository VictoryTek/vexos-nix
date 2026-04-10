# Review: Fix `vexos-privacy-vm` impermanence assertion failure

**Feature:** `privacy_vm_assert`  
**Reviewer:** Review Subagent  
**Date:** 2026-04-10  
**Files reviewed:**  
- `flake.nix`  
- `template/etc-nixos-flake.nix`  
- `modules/privacy-disk.nix`  
- `modules/impermanence.nix`  
- `hosts/privacy-vm.nix`  
- `.github/docs/subagent_docs/privacy_vm_assert_spec.md`

---

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 95% | A |
| Functionality | 100% | A |
| Code Quality | 97% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 97% | A |
| Build Success (static analysis) | 100% | A |

**Overall Grade: A (99%)**

---

## Spec Compliance Checklist

| Item | Status |
|------|--------|
| `privacyBase` has `{ lib, ... }:` signature | ✅ PASS |
| `privacyBase` imports `./modules/privacy-disk.nix` | ✅ PASS |
| `privacyBase` sets `vexos.privacy.disk.enable = true` | ✅ PASS |
| `privacyBase` sets `vexos.privacy.disk.device = lib.mkDefault "/dev/nvme0n1"` | ✅ PASS |
| `privacyBase` sets `vexos.privacy.disk.enableLuks = lib.mkDefault true` | ✅ PASS |
| New `privacyGpuVm` module in `nixosModules` before `asus` | ✅ PASS |
| `privacyGpuVm` has `{ lib, ... }:` signature | ✅ PASS |
| `privacyGpuVm` imports `./modules/gpu/vm.nix` | ✅ PASS |
| `privacyGpuVm` sets `vexos.privacy.disk.device = lib.mkForce "/dev/vda"` | ✅ PASS |
| `privacyGpuVm` sets `vexos.privacy.disk.enableLuks = lib.mkForce false` | ✅ PASS |
| `template/etc-nixos-flake.nix` uses `privacyGpuVm` for `vexos-privacy-vm` | ✅ PASS |
| `hosts/privacy-vm.nix` is UNCHANGED | ✅ PASS |

---

## Logic Correctness

| Item | Status | Notes |
|------|--------|-------|
| Wrapper path: `privacy-disk.nix` now imported → `neededForBoot = true` → assertion passes | ✅ PASS | `privacyBase` imports `privacy-disk.nix`; `cfg.enable = true` activates `lib.mkForce true` on `neededForBoot` |
| VM variant: `lib.mkForce` in `privacyGpuVm` beats `lib.mkDefault` in `privacyBase` | ✅ PASS | Force (1500+50) > Default (1000) — correct device and no LUKS |
| Bare-metal variants: `lib.mkDefault` values apply correctly | ✅ PASS | `gpuAmd/gpuNvidia/gpuIntel` do not set `vexos.privacy.disk.*` so defaults hold |
| Direct `nixosConfigurations.vexos-privacy-vm` is unaffected | ✅ PASS | Uses `hosts/privacy-vm.nix` directly; `privacyBase` is not in that module graph |
| `disko.nixosModules.disko` and `privacy-disk.nix` coexist without conflict | ✅ PASS | Former provides NixOS module machinery; latter configures `disko.devices` — no overlap |
| `privacy-disk.nix` uses `lib.mkForce true` for `neededForBoot` | ✅ PASS | Confirmed in `modules/privacy-disk.nix` lines 152–153 |

---

## Static Build Validation

Running on Windows — `nix` commands not available. Static analysis performed instead.

| Check | Status |
|-------|--------|
| `modules/gpu/vm.nix` exists | ✅ Confirmed |
| `modules/privacy-disk.nix` exists | ✅ Confirmed |
| `flake.nix` brace balance | ✅ Balanced — `nixosModules` attrset closes with `};`, `outputs` closes with `};`, flake closes with `}` |
| All import paths in `privacyBase` resolve to existing files | ✅ Confirmed — `./configuration-privacy.nix`, `./modules/privacy-disk.nix` both exist |
| All import paths in `privacyGpuVm` resolve to existing files | ✅ Confirmed — `./modules/gpu/vm.nix` exists |
| `template/etc-nixos-flake.nix` references `vexos-nix.nixosModules.privacyGpuVm` (now defined) | ✅ Confirmed |
| `hardware-configuration.nix` NOT tracked in repo | ✅ Confirmed — not present in workspace |

---

## NixOS-Specific Concerns

| Concern | Verdict |
|---------|---------|
| Duplicate option declarations between `privacyBase` and `hosts/privacy-vm.nix` | ✅ No conflict — these are on separate, mutually exclusive code paths |
| Double-import of `disko.nixosModules.disko` in full `nixosConfigurations` path | ✅ Safe — NixOS deduplicates imports by path |
| `enable = true` is plain assignment (not `mkDefault`) in `privacyBase` | ✅ Correct — privacy role always requires the disk module; there is no legitimate use case for a `privacyBase` build without disk config |
| Priority ordering: `mkForce` in `privacyGpuVm` vs `mkDefault` in `privacyBase` | ✅ Correct — mkForce (1500+50) wins over mkDefault (1000) |
| `vexos.privacy.disk.enable` not set in `privacyGpuVm` | ✅ Safe — `privacyBase` sets it `true` (plain); this propagates to the VM path unchanged |

---

## Critical Issues

**None.**

---

## Minor Observations (non-blocking)

1. **Cosmetic alignment in `template/etc-nixos-flake.nix`:** The `vexos-privacy-vm` line uses `    ` (4 spaces) for column padding after the variant string, matching existing style. Since `privacyGpuVm` is longer than `gpuVm`, the right-hand module reference no longer column-aligns with the bare-metal variants. This is a purely cosmetic inconsistency with zero functional impact.

2. **`privacyGpuVm` could include a guard for `virtualisation.virtualbox.guest.enable`:** The `gpuAmd/gpuNvidia/gpuIntel` modules use `lib.mkForce false` to prevent VirtualBox guest additions from accidentally being enabled. `gpuVm` (the bare desktop VM module) intentionally omits this guard. `privacyGpuVm` follows `gpuVm`'s pattern, which is appropriate — the VM IS a VM and may legitimately want VBox guest additions. No action required.

3. **Wrapper users with old `/etc/nixos/flake.nix` still reference `gpuVm`:** The spec correctly identifies this as a known risk (§5.1). The fix is one-line for affected users. No action required in this implementation.

---

## Summary

The implementation is fully correct. All 12 spec compliance items pass. The root cause — `privacy-disk.nix` never being imported in the `nixosModules.privacyBase` wrapper path — is addressed by importing it directly in `privacyBase` with `lib.mkDefault` values. The new `privacyGpuVm` module correctly overrides the VM-specific settings using `lib.mkForce`, and the priority hierarchy (`mkForce` > plain > `mkDefault`) ensures correct merged values for every variant. The direct `nixosConfigurations` path is untouched. No critical issues were found.

---

## Result

**PASS**
