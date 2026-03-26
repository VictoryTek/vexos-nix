# Review: `vexos-intel` NixOS Variant

**Date:** 2026-03-26  
**Reviewer:** Review & Quality Assurance Subagent  
**Spec:** `.github/docs/subagent_docs/intel_variant_spec.md`  
**Files Reviewed:**
- `modules/gpu/intel.nix` (new)
- `hosts/intel.nix` (new)
- `flake.nix` (modified)
- `configuration.nix` (reference — not modified)
- `modules/gpu/amd.nix` (style reference)
- `hosts/amd.nix` (style reference)
- `modules/gpu.nix` (base GPU module reference)

---

## Verdict: PASS

No CRITICAL issues found. Implementation is a faithful, correct match to the specification.

---

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A+ |
| Best Practices | 95% | A |
| Functionality | 100% | A+ |
| Code Quality | 97% | A+ |
| Security | 100% | A+ |
| Performance | 100% | A+ |
| Consistency | 98% | A+ |
| Build Success | 85% | B+ |

**Overall Grade: A+ (97%)**

---

## Build Validation Results

| Check | Result | Notes |
|-------|--------|-------|
| `nix flake show` | ✅ PASSED | All four configurations and all six nixosModules visible |
| `modules/gpu/intel.nix` Nix parse | ✅ PASSED | `builtins.typeOf` returns `"lambda"` — valid Nix function |
| `hosts/intel.nix` Nix parse | ✅ PASSED | `builtins.typeOf` returns `"lambda"` — valid Nix function |
| `nix flake check` (full eval) | ⚠️ SKIPPED | Blocked by missing `/etc/nixos/hardware-configuration.nix` in WSL environment — see note below |
| `nixos-rebuild dry-build` | ⚠️ SKIPPED | Same reason |

**Note on `nix flake check` result:** The failure `path '/etc/nixos/hardware-configuration.nix' does not exist` affects all four configurations (`vexos-amd`, `vexos-nvidia`, `vexos-vm`, `vexos-intel`) equally and is the documented Risk 7 from the specification. It is not a defect in the Intel implementation. `nix flake show` parsed and evaluated the full flake structure including `vexos-intel` and `gpuIntel` without errors, confirming the Nix expression is syntactically and structurally valid.

---

## Specification Compliance

### modules/gpu/intel.nix

| Spec Item | Required | Implemented | Status |
|-----------|----------|-------------|--------|
| i915 initrd kernel module | `boot.initrd.kernelModules = [ "i915" ]` | ✅ Present | PASS |
| GuC/HuC kernel param | `boot.kernelParams = [ "i915.enable_guc=3" ]` | ✅ Present | PASS |
| Redistributable firmware | `hardware.enableRedistributableFirmware = true` | ✅ Present | PASS |
| iHD env var | `environment.sessionVariables.LIBVA_DRIVER_NAME = "iHD"` | ✅ Present | PASS |
| Quick Sync Video | `vpl-gpu-rt` in `extraPackages` | ✅ Present | PASS |
| OpenCL runtime | `intel-compute-runtime` in `extraPackages` | ✅ Present | PASS |
| 32-bit iHD VA-API | `pkgsi686Linux.intel-media-driver` in `extraPackages32` | ✅ Present | PASS |
| GPU tools | `intel-gpu-tools` in `systemPackages` | ✅ Present | PASS |
| Arc/xe override comment | Module header with xe instructions | ✅ Present | PASS |

### hosts/intel.nix

| Spec Item | Required | Implemented | Status |
|-----------|----------|-------------|--------|
| Imports `configuration.nix` | `../configuration.nix` | ✅ Present | PASS |
| Imports GPU module | `../modules/gpu/intel.nix` | ✅ Present | PASS |
| Does NOT import `asus.nix` | Intentionally omitted | ✅ Absent | PASS |
| Header comment with rebuild command | Present | ✅ Present | PASS |

### flake.nix

| Spec Item | Required | Implemented | Status |
|-----------|----------|-------------|--------|
| `vexos-intel` nixosConfiguration | Added after `vexos-vm` | ✅ Present | PASS |
| Follows same pattern | `commonModules ++ [ ./hosts/intel.nix ]` | ✅ Matches | PASS |
| `specialArgs = { inherit inputs; }` | Present | ✅ Present | PASS |
| `gpuIntel` in nixosModules | `gpuIntel = ./modules/gpu/intel.nix;` | ✅ Present | PASS |
| No new flake inputs | No new inputs added | ✅ Confirmed | PASS |

---

## NixOS Correctness

| Check | Expected | Actual | Status |
|-------|----------|--------|--------|
| `hardware.graphics.extraPackages` (not `hardware.opengl`) | `hardware.graphics.*` (NixOS 24.05+) | ✅ Correct | PASS |
| `hardware.graphics.extraPackages32` | Correct attribute | ✅ Correct | PASS |
| `environment.sessionVariables` (not `environment.variables`) | `sessionVariables` for user-facing LIBVA_DRIVER_NAME | ✅ Correct | PASS |
| Package `vpl-gpu-rt` | Valid in nixpkgs 25.11 (v25.4.1) | ✅ Correct | PASS |
| Package `intel-compute-runtime` | Valid in nixpkgs 25.11 (v25.44.36015.5) | ✅ Correct | PASS |
| Package `intel-gpu-tools` | Valid in nixpkgs 25.11 (v2.2) | ✅ Correct | PASS |
| Package `pkgsi686Linux.intel-media-driver` | 32-bit iHD VA-API | ✅ Correct | PASS |
| Kernel params syntax | `[ "i915.enable_guc=3" ]` | ✅ Correct | PASS |
| `hardware.enableRedistributableFirmware` | Correct top-level hw option | ✅ Correct | PASS |

---

## Style Consistency

| Check | Status | Notes |
|-------|--------|-------|
| Header comment format | ✅ PASS | `# modules/gpu/intel.nix` + description line — matches `amd.nix` exactly |
| 2-space Nix indentation | ✅ PASS | Consistent throughout all new files |
| Host file format | ✅ PASS | Matches `hosts/amd.nix` pattern: thin host, header comment, imports block |
| Inline comment style | ✅ PASS | Consistent with `amd.nix` (brand modules don't use `# ── Label ──` section dividers — appropriate for their size) |
| `{ config, pkgs, lib, ... }:` signature | ✅ PASS | Matches `amd.nix` signature; unused args are harmless and idiomatic in NixOS modules |

---

## Critical Checks

| Check | Status |
|-------|--------|
| `hardware-configuration.nix` NOT in repository | ✅ PASS — file search confirmed absent; only referenced as `/etc/nixos/hardware-configuration.nix` absolute path in `flake.nix` |
| `system.stateVersion` NOT changed | ✅ PASS — remains `"25.11"` at `configuration.nix:126` |
| No duplicate module imports | ✅ PASS — `hosts/intel.nix` imports `configuration.nix` + `modules/gpu/intel.nix`; no overlap |
| `modules/asus.nix` intentionally excluded | ✅ PASS — per spec §4.3: ASUS module is for AMD/NVIDIA hardware only |

---

## Observations (Non-Critical)

1. **Unused `lib` argument in `intel.nix` signature** — `{ config, pkgs, lib, ... }:` includes `lib` which is not referenced in the module body. This is consistent with `amd.nix`'s signature pattern and is harmless in NixOS modules (arguments are passed via the module system regardless). No action required.

2. **`intel-compute-runtime` comment recommends `-legacy1` for Gen8–11** — The inline comment correctly documents that `intel-compute-runtime-legacy1` should be substituted for older iGPUs. This is the appropriate approach (module comment vs. adding unnecessary conditional logic). Good practice.

3. **`nix flake show` outputs `vexos-intel`** confirmed alongside all existing configurations and modules — the flake's attrset structure is correct with no regressions to existing outputs.

---

## Summary

The `vexos-intel` implementation is a precise, correct realisation of the specification. All required NixOS options, package names, environment variables, attribute paths, flake outputs, and module exports are present and correctly configured. Style is consistent with the existing codebase. No deprecated attributes (`hardware.opengl`) were used. The choice of `environment.sessionVariables` over `environment.variables` is correct. The Arc/xe override documentation in the module header satisfies the forward-compatibility requirement for Battlemage/Meteor Lake hardware.

Build validation was partially constrained by the absence of `/etc/nixos/hardware-configuration.nix` in the WSL review environment — this is the expected limitation documented in spec Risk 7 and is not attributable to the Intel implementation. Nix syntax was confirmed valid via `nix flake show` (full flake evaluation tree) and direct `nix eval` parse checks on both new files.

**Result: PASS — No refinement required.**
