# ASUS Hardware Option — Review & QA
**Feature:** `vexos.hardware.asus.enable` — universal opt-in ASUS ROG/TUF hardware support  
**Spec:** `.github/docs/subagent_docs/asus_hardware_option_spec.md`  
**Date:** 2026-05-15  
**Reviewer:** QA Subagent  

---

## Result: NEEDS_REFINEMENT

Two issues prevent this from passing: one **CRITICAL** (build-breaking static analysis failure), one **MISSING** (incomplete spec coverage). Both must be resolved before re-review.

---

## Critical Issues

### [CRITICAL] `flake.nix` line 347 references the deleted `modules/asus.nix`

```
flake.nix:347    asus = ./modules/asus.nix;
```

`modules/asus.nix` was correctly deleted as part of this feature. However, the `nixosModules` attrset in `flake.nix` was not updated. The `asus` nixosModule export still points to the deleted file. **`nix flake check` will fail with a missing-file error.**

**Required fix:** Update `flake.nix` line 347:

```nix
# Before (broken — file deleted):
asus = ./modules/asus.nix;

# After:
asus = ./modules/asus-opt.nix;
```

This preserves the public `nixosModules.asus` API while pointing to the live replacement.

---

### [MISSING] `configuration-vanilla.nix` not updated per spec

The spec explicitly lists `configuration-vanilla.nix` in the change table (section 3.3) and requires adding `./modules/asus-opt.nix` to its imports. This was not done.

```nix
# configuration-vanilla.nix — current imports list (asus-opt.nix absent):
imports = [
  ./modules/locale.nix
  ./modules/users.nix
  ./modules/nix.nix
];
```

Without this import, the `vexos.hardware.asus.enable` option is undeclared for vanilla role builds. Any vanilla host on ASUS hardware that attempts to set `vexos.hardware.asus.enable = true` will fail evaluation with `"undefined option"`.

**Required fix:** Add `./modules/asus-opt.nix` to the imports list in `configuration-vanilla.nix`.

---

## Passing Checks

### Specification Compliance

| Check | Result |
|---|---|
| `modules/asus-opt.nix` exists | ✅ PASS |
| Declares `options.vexos.hardware.asus.enable` via `lib.mkEnableOption` | ✅ PASS |
| All ASUS config inside `config = lib.mkIf config.vexos.hardware.asus.enable { }` | ✅ PASS |
| `modules/asus.nix` deleted (file not found) | ✅ PASS |
| `configuration-desktop.nix` imports `asus-opt.nix` | ✅ PASS |
| `configuration-server.nix` imports `asus-opt.nix` | ✅ PASS |
| `configuration-htpc.nix` imports `asus-opt.nix` | ✅ PASS |
| `configuration-headless-server.nix` imports `asus-opt.nix` | ✅ PASS |
| `configuration-stateless.nix` imports `asus-opt.nix` | ✅ PASS |
| `configuration-vanilla.nix` imports `asus-opt.nix` | ❌ MISSING |
| `hosts/desktop-amd.nix` has `vexos.hardware.asus.enable = true`, no direct asus.nix import | ✅ PASS |
| `hosts/desktop-nvidia.nix` has `vexos.hardware.asus.enable = true`, no direct asus.nix import | ✅ PASS |
| `hosts/desktop-intel.nix` has `vexos.hardware.asus.enable = true`, no direct asus.nix import | ✅ PASS |
| `hosts/desktop-vm.nix` has no `vexos.hardware.asus.enable = true`, no direct asus.nix import | ✅ PASS |
| `flake.nix` nixosModules.asus updated to reference live file | ❌ CRITICAL |

### Code Quality

| Check | Result |
|---|---|
| Module function signature `{ config, lib, pkgs, ... }:` | ✅ PASS |
| Option type uses `lib.mkEnableOption` | ✅ PASS |
| Default is `false` (mkEnableOption default) | ✅ PASS |
| No circular imports | ✅ PASS |
| `services.asusd.enable = true` preserved | ✅ PASS |
| `services.asusd.enableUserService = true` preserved | ✅ PASS |
| `services.supergfxd.enable = true` preserved | ✅ PASS |
| `environment.systemPackages = [ asusctl ]` preserved | ✅ PASS |

All content from original `asus.nix` is fully present under `lib.mkIf`.

### Architecture

| Check | Result |
|---|---|
| `lib.mkIf` is a hardware-flag gate, not a role gate | ✅ PASS |
| Server/htpc/stateless/headless-server hosts correctly default to false (option not set) | ✅ PASS |
| No role-specific `lib.mkIf` guards added to `configuration-*.nix` files | ✅ PASS |
| VM correctly absent — `vexos.hardware.asus.enable` not set in `hosts/desktop-vm.nix` | ✅ PASS |
| The commented-out `# vexos.hardware.asus.enable = false; # VM` in desktop-vm.nix serves as documentation; option defaults false and is harmless | ✅ ACCEPTABLE |

### Minor Observations (Non-Blocking)

- `modules/asus-opt.nix` header comment reads `# Hardware-agnostic wrapper for asus.nix.` — the file it references is now deleted. The comment is slightly misleading but self-contained; recommend updating to `# Opt-in ASUS ROG/TUF hardware support.` in a future cleanup pass. Not blocking.

### Build Validation

`nix flake check` is **deferred to CI — nix unavailable on Windows host.**

However, static analysis identified one definitive build failure: `flake.nix:347` references `./modules/asus.nix`, which no longer exists on disk (confirmed by file search returning no results). This will produce a missing-file evaluation error in any `nix` invocation that touches `nixosModules.asus`. Classified as CRITICAL.

---

## Score Table

| Category | Score | Grade |
|---|---|-------|
| Specification Compliance | 85% | B |
| Best Practices | 95% | A |
| Functionality | 80% | B- |
| Code Quality | 90% | A- |
| Security | 100% | A+ |
| Performance | 100% | A+ |
| Consistency | 85% | B |
| Build Success | 20% | F |

**Overall Grade: C+ (82%)**

---

## Required Actions Before Re-Review

1. **[CRITICAL] Fix `flake.nix` line 347:** Change `asus = ./modules/asus.nix;` to `asus = ./modules/asus-opt.nix;`
2. **[MISSING] Update `configuration-vanilla.nix`:** Add `./modules/asus-opt.nix` to its imports list

No other changes required. The core implementation in `asus-opt.nix`, all five targeted `configuration-*.nix` files, and all four `hosts/desktop-*.nix` files are correctly implemented per spec.
