# Specification: `vexos-intel` NixOS System Variant

**Date:** 2026-03-26  
**Author:** Research & Specification Subagent  
**Target Branch:** nixos-25.11 (actual channel in use per `flake.nix`)  
**Spec Path:** `.github/docs/subagent_docs/intel_variant_spec.md`

---

## 1. Current State Analysis

### 1.1 Existing Flake Outputs

`flake.nix` currently defines three `nixosConfigurations` outputs:

| Output | Host File | GPU Module |
|---|---|---|
| `vexos-amd` | `hosts/amd.nix` | `modules/gpu/amd.nix` |
| `vexos-nvidia` | `hosts/nvidia.nix` | `modules/gpu/nvidia.nix` |
| `vexos-vm` | `hosts/vm.nix` | `modules/gpu/vm.nix` |

The flake also exports a `nixosModules` attrset that exposes `gpuAmd`, `gpuNvidia`, `gpuVm`, `asus`, and `base`.

### 1.2 Architecture Pattern

```
hosts/<name>.nix
  → imports ../configuration.nix
  → imports ../modules/gpu/<name>.nix
  → optional: imports ../modules/asus.nix (ASUS-specific hardware)
```

`configuration.nix` imports `modules/gpu.nix` — the **common GPU base module**. All GPU-brand-specific configuration lives in `modules/gpu/<brand>.nix` and is imported only by the relevant host file.

### 1.3 Common GPU Base (modules/gpu.nix) — What Is Already Set

The following Intel-relevant settings are **already present** in the shared base module and do NOT need to be repeated in the Intel-specific module:

| Setting | Value | Notes |
|---|---|---|
| `hardware.graphics.enable` | `true` | DRI, Mesa GL/Vulkan enabled |
| `hardware.graphics.enable32Bit` | `true` | Required for Steam/Proton |
| `hardware.graphics.extraPackages` includes `intel-media-driver` | ✓ | iHD VA-API for all builds |
| `hardware.graphics.extraPackages` includes `mesa` | ✓ | ANV Vulkan included |
| `hardware.graphics.extraPackages` includes `libva` | ✓ | VA-API runtime |
| `hardware.graphics.extraPackages32` includes `libva`, `mesa` | ✓ | 32-bit coverage |
| `environment.systemPackages` includes `ffmpeg-full`, `libva-utils`, `vulkan-tools` | ✓ | Diagnostic tools |

### 1.4 What Is Missing for Intel

The following Intel-specific capabilities are **not** provided by any current module:

- Early KMS loading of `i915` kernel module in initrd
- GuC firmware and HuC media-decode acceleration (`i915.enable_guc=3`)
- `hardware.enableRedistributableFirmware` (needed for GuC/HuC firmware blobs)
- Explicit `LIBVA_DRIVER_NAME=iHD` environment variable (ensures the modern driver wins over the legacy `i965` fallback)
- Intel Quick Sync Video (QSV) via `vpl-gpu-rt` (oneVPL GPU runtime; Gen12+)
- Intel OpenCL/Level Zero compute runtime (`intel-compute-runtime`, Gen12+)
- Intel GPU diagnostic tooling (`intel-gpu-tools`)
- 32-bit iHD VA-API coverage (`intel-media-driver` i686 variant; needed by Steam/Proton)
- `hosts/intel.nix` host definition
- `vexos-intel` flake output
- `gpuIntel` nixosModule export

---

## 2. Problem Definition

There is no `vexos-intel` configuration for machines with:

- **Intel integrated graphics** (Intel 8th–14th generation iGPU, UHD / Iris Xe)
- **Intel Arc discrete GPU** — Arc A-series (Alchemist, i915 driver) or Arc B-series / Meteor Lake / Lunar Lake (xe driver)
- Hybrid Intel iGPU + Intel Arc setups

Without a dedicated Intel GPU module, attempting to run on such hardware would miss GuC/HuC firmware loading, produce degraded VA-API performance (wrong driver backend), lack QSV hardware-encode capability, and miss OpenCL compute support for Arc/Xe GPUs.

---

## 3. Research Sources

| # | Source | Finding |
|---|---|---|
| 1 | [NixOS Wiki — Intel Graphics](https://wiki.nixos.org/wiki/Intel_Graphics) | Configuration example with `LIBVA_DRIVER_NAME`, `vpl-gpu-rt`, `intel-compute-runtime`, `i915.enable_guc=3`, `hardware.enableRedistributableFirmware` |
| 2 | [NixOS Wiki — Accelerated Video Playback](https://wiki.nixos.org/wiki/Accelerated_Video_Playback) | `intel-media-driver` (iHD) for Broadwell+; `intel-vaapi-driver` (i965) for older; `extraPackages32` pattern |
| 3 | [Arch Linux Wiki — Intel graphics](https://wiki.archlinux.org/title/Intel_graphics) | GuC/HuC kernel param table (`enable_guc` values 0–3), Early KMS via `i915`/`xe`, `xe` driver requires kernel 6.8+ |
| 4 | [NixOS search — `intel-compute-runtime`](https://search.nixos.org/packages?query=intel-compute-runtime) | Package `intel-compute-runtime` (Gen12+, version 25.44.36015.5) and `intel-compute-runtime-legacy1` (Gen8–11) confirmed in nixpkgs 25.11 |
| 5 | [NixOS search — `intel-gpu-tools`](https://search.nixos.org/packages?query=intel-gpu-tools) | Package `intel-gpu-tools` version 2.2 confirmed in nixpkgs 25.11 |
| 6 | [NixOS search — `vpl-gpu-rt`](https://search.nixos.org/packages?channel=25.11&query=vpl-gpu-rt) | Package `vpl-gpu-rt` (Intel oneVPL GPU runtime, version 25.4.1) confirmed in nixpkgs 25.11; replaces deprecated `intel-media-sdk` |
| 7 | [nixos-hardware — `common/gpu/intel/default.nix`](https://github.com/NixOS/nixos-hardware/blob/master/common/gpu/intel/default.nix) | Canonical nixos-hardware module: `driver = "i915"\|"xe"` option; maps to `boot.initrd.kernelModules`; `xe` requires kernel ≥ 6.8; `intel-compute-runtime-legacy1` for Gen8–11 |
| 8 | [nixos-hardware — `common/gpu/intel/lunar-lake/default.nix`](https://github.com/NixOS/nixos-hardware/blob/master/common/gpu/intel/lunar-lake/default.nix) | Lunar Lake uses `driver = "xe"` (conditioned on kernel ≥ 6.8), `vaapiDriver = "intel-media-driver"` |

---

## 4. Proposed Solution Architecture

### 4.1 Files to Create

| File | Purpose |
|---|---|
| `modules/gpu/intel.nix` | Intel GPU module (i915 initrd, GuC/HuC, iHD VA-API, QSV, OpenCL, tools) |
| `hosts/intel.nix` | Intel host definition (imports configuration.nix + modules/gpu/intel.nix) |

### 4.2 Files to Modify

| File | Change |
|---|---|
| `flake.nix` | Add `vexos-intel` nixosConfiguration output; add `gpuIntel = ./modules/gpu/intel.nix` to `nixosModules` |

### 4.3 Scope Boundary

- `hardware-configuration.nix` MUST NOT be added to this repo — it stays at `/etc/nixos/` on the host.
- `system.stateVersion` in `configuration.nix` MUST NOT be changed.
- `modules/asus.nix` is NOT imported by `hosts/intel.nix` — that module is ASUS-specific to the AMD/NVIDIA builds.

---

## 5. Exact NixOS Options and Package Names

### 5.1 Kernel Module and Early KMS

```nix
# i915 driver: Intel integrated graphics and Arc A-series (Alchemist)
boot.initrd.kernelModules = [ "i915" ];
```

The `i915` module covers:
- Intel 6th gen (Skylake) through 13th gen (Raptor Lake) integrated graphics
- Intel Arc A-series discrete (Alchemist)

For **Intel Arc B-series (Battlemage), Meteor Lake, or Lunar Lake**, the `xe` driver is required instead:

```nix
# xe driver: Arc B-series (Battlemage), Meteor Lake, Lunar Lake — kernel 6.8+ required
boot.initrd.kernelModules = [ "xe" ];
```

The CachyOS kernel used in this project is Linux 6.x and satisfies the xe ≥ 6.8 requirement. However, the spec targets `i915` as the default because it covers the broadest range of Intel hardware (including Arc A); xe should be an opt-in override at the host level once the user knows their GPU generation.

### 5.2 GuC / HuC Firmware (i915 only)

```nix
# i915.enable_guc=3: enable GuC CPU submission + HuC media decode acceleration
# - GuC submission: Gen12 (Alder Lake-P mobile) default; earlier requires opt-in
# - HuC loading: Gen9 (Skylake) and newer when enable_guc includes bit 1 (value 2 or 3)
# WARNING: taints the kernel on hardware that doesn't support it; remove if freezes occur
boot.kernelParams = [ "i915.enable_guc=3" ];
```

**Important:** The `xe` driver enables GuC and HuC automatically. If the host switches to `xe`, these kernel params MUST be removed.

### 5.3 Redistributable Firmware

```nix
# Provides GuC and HuC firmware blobs (i915/<gpu>_guc_*.bin, i915/<gpu>_huc_*.bin)
hardware.enableRedistributableFirmware = true;
```

### 5.4 VA-API — iHD Driver Selection

```nix
environment.sessionVariables = {
  # Force the modern iHD backend (intel-media-driver, Broadwell 2014+)
  # Prevents fallback to the legacy i965 backend on Skylake+ systems
  LIBVA_DRIVER_NAME = "iHD";
};
```

Note: `intel-media-driver` is already included in the base `modules/gpu.nix` `extraPackages` for all builds. The Intel-specific module sets the env var to guarantee iHD is selected at runtime.

### 5.5 Quick Sync Video — Intel VPL (QSV)

```nix
hardware.graphics.extraPackages = with pkgs; [
  vpl-gpu-rt          # Intel oneVPL GPU runtime: hardware video encode/decode (QSV)
                      # Package: vpl-gpu-rt v25.4.1, confirmed in nixpkgs 25.11
                      # Supersedes deprecated intel-media-sdk; required for Gen12+ QSV
  ...
];
```

### 5.6 OpenCL and Level Zero Compute

```nix
hardware.graphics.extraPackages = with pkgs; [
  ...
  intel-compute-runtime   # OpenCL NEO + Level Zero: GPU compute on Arc/Xe/12th gen+
                          # Package: intel-compute-runtime v25.44.36015.5, nixpkgs 25.11
                          # For Gen8–11 (pre-12th gen), use intel-compute-runtime-legacy1 instead
];
```

### 5.7 Vulkan

Intel's Vulkan driver (ANV — Anvil) is part of **Mesa** and is automatically enabled when `hardware.graphics.enable = true` and `mesa` is in `extraPackages`. Both are already set in `modules/gpu.nix`. **No additional packages or configuration are required.**

### 5.8 32-bit VA-API (Steam / Proton)

```nix
hardware.graphics.extraPackages32 = with pkgs.pkgsi686Linux; [
  intel-media-driver   # 32-bit iHD VA-API: required for Steam/Proton 32-bit VA-API access
                       # NOT present in modules/gpu.nix extraPackages32 — must be added here
];
```

### 5.9 Intel GPU Tooling

```nix
environment.systemPackages = with pkgs; [
  intel-gpu-tools      # intel_gpu_top, IGT benchmarks, GPU activity monitoring
                       # Package: intel-gpu-tools v2.2, nixpkgs 25.11
];
```

---

## 6. Complete Module Implementation

### 6.1 `modules/gpu/intel.nix`

```nix
# modules/gpu/intel.nix
# Intel GPU: i915 early KMS, GuC/HuC firmware, iHD VA-API, QSV (VPL), OpenCL (NEO).
# Covers Intel 8th gen+ integrated graphics and Intel Arc A-series (Alchemist) discrete.
#
# For Intel Arc B-series (Battlemage), Meteor Lake, or Lunar Lake:
#   1. Replace boot.initrd.kernelModules = [ "i915" ] with [ "xe" ]
#   2. Remove boot.kernelParams i915.enable_guc=3 (xe enables GuC/HuC automatically)
#
# Do NOT use alongside gpu/amd.nix, gpu/nvidia.nix, or gpu/vm.nix.
{ config, pkgs, lib, ... }:
{
  # Load i915 kernel module at stage 1 for early KMS (correct framebuffer from boot)
  boot.initrd.kernelModules = [ "i915" ];

  # GuC submission + HuC firmware loading for i915 (Gen9 / Skylake and newer)
  # enable_guc=3: bit 0 = GuC submission, bit 1 = HuC firmware load
  # The xe driver enables these automatically — remove this param if switching to xe.
  boot.kernelParams = [ "i915.enable_guc=3" ];

  # Required for GuC/HuC firmware blobs (i915/<gpu>_guc_*.bin, i915/<gpu>_huc_*.bin)
  hardware.enableRedistributableFirmware = true;

  # Prefer the modern iHD VA-API backend (intel-media-driver, Broadwell 2014+)
  # intel-media-driver is already included via modules/gpu.nix extraPackages.
  # This env var prevents silent fallback to the legacy i965 (intel-vaapi-driver).
  environment.sessionVariables = {
    LIBVA_DRIVER_NAME = "iHD";
  };

  # Intel-specific graphics acceleration (appended to base packages in modules/gpu.nix)
  hardware.graphics.extraPackages = with pkgs; [
    vpl-gpu-rt              # Intel oneVPL: Quick Sync Video hardware encode/decode (Gen12+)
    intel-compute-runtime   # OpenCL NEO + Level Zero: GPU compute on Arc/Xe/12th gen+
                            # Replace with intel-compute-runtime-legacy1 for Gen8–11 iGPUs
  ];

  # 32-bit iHD VA-API — required by Steam/Proton 32-bit applications
  # (intel-media-driver 32-bit is not included in the base modules/gpu.nix extraPackages32)
  hardware.graphics.extraPackages32 = with pkgs.pkgsi686Linux; [
    intel-media-driver
  ];

  # Intel GPU diagnostic and monitoring tools
  environment.systemPackages = with pkgs; [
    intel-gpu-tools    # intel_gpu_top, IGT benchmarks
  ];
}
```

### 6.2 `hosts/intel.nix`

```nix
# hosts/intel.nix
# vexos — Intel GPU system build (integrated iGPU or Arc A-series discrete).
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-intel
{ ... }:
{
  imports = [
    ../configuration.nix
    ../modules/gpu/intel.nix
  ];
}
```

Note: `modules/asus.nix` is intentionally NOT imported — ASUS-specific settings are AMD/NVIDIA platform features. Add it back if the target hardware is an ASUS board.

### 6.3 `flake.nix` Changes

#### 6.3.1 Add `vexos-intel` nixosConfiguration

Add the following block after the `vexos-vm` nixosConfiguration (before the `nixosModules` attrset):

```nix
    # ── Intel GPU build ──────────────────────────────────────────────────────
    # sudo nixos-rebuild switch --flake .#vexos-intel
    nixosConfigurations.vexos-intel = nixpkgs.lib.nixosSystem {
      inherit system;
      modules = commonModules ++ [ ./hosts/intel.nix ];
      specialArgs = { inherit inputs; };
    };
```

#### 6.3.2 Add `gpuIntel` to `nixosModules`

Add to the `nixosModules` attrset (alongside `gpuAmd`, `gpuNvidia`, `gpuVm`):

```nix
      gpuIntel  = ./modules/gpu/intel.nix;
```

---

## 7. Implementation Steps (Ordered)

1. **Create `modules/gpu/intel.nix`** — implement exactly as specified in §6.1 above.

2. **Create `hosts/intel.nix`** — implement exactly as specified in §6.2 above.

3. **Modify `flake.nix`** — apply both changes from §6.3:
   - Insert `nixosConfigurations.vexos-intel` block after `vexos-vm` and before `nixosModules`.
   - Add `gpuIntel = ./modules/gpu/intel.nix;` to the `nixosModules` attrset.

4. **Validate** — run:
   ```bash
   nix flake check
   sudo nixos-rebuild dry-build --flake .#vexos-intel
   ```

---

## 8. Dependencies

All required packages are available in nixpkgs 25.11. No new flake inputs are needed.

| Package | nixpkgs Attribute | Version (25.11) | Notes |
|---|---|---|---|
| Intel iHD VA-API | `pkgs.intel-media-driver` | Current | Already in `modules/gpu.nix` base |
| Intel oneVPL GPU runtime (QSV) | `pkgs.vpl-gpu-rt` | 25.4.1 | New — add to Intel module |
| Intel OpenCL / Level Zero (Gen12+) | `pkgs.intel-compute-runtime` | 25.44.36015.5 | New — add to Intel module |
| Intel OpenCL / Level Zero (Gen8–11) | `pkgs.intel-compute-runtime-legacy1` | 24.35.30872.32 | Optional — for pre-12th gen iGPU |
| Intel GPU tools | `pkgs.intel-gpu-tools` | 2.2 | New — add to Intel module |
| 32-bit iHD VA-API | `pkgs.pkgsi686Linux.intel-media-driver` | Current | New — add to Intel module |
| Mesa (ANV Vulkan) | `pkgs.mesa` (already in base) | Current | No change needed |

---

## 9. Risks and Mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| `i915.enable_guc=3` taints kernel on unsupported hardware (pre-Gen9) | Low | Comment in module; user removes the param if hardware doesn't support it. Gen9+ (Skylake 2015+) is the mainstream target. |
| Arc B-series / Battlemage requires `xe` not `i915` | Medium | Module header comment explicitly documents the `i915 → xe` swap and GuC param removal. The spec uses i915 as the safe default for maximum compatibility. |
| `intel-compute-runtime` only handles Gen12+; older iGPUs (8th–11th gen) need `-legacy1` | Low–Medium | Module comment documents `intel-compute-runtime-legacy1` as the drop-in substitute. The OpenCL failure mode is silent (app falls back to CPU); it does not break boot. |
| `hardware.enableRedistributableFirmware = true` may conflict with strict `allowUnfree = false` setups | None | `configuration.nix` already sets `nixpkgs.config.allowUnfree = true`, eliminating this concern. |
| `LIBVA_DRIVER_NAME=iHD` hides `intel-vaapi-driver` (i965) for browsers that may prefer it | Very Low | The variable is set via `sessionVariables` (not `environment.variables`) so it can be overridden per-application. Skylake-era browser VA-API quirk is a narrow edge case not expected in this project's usage. |
| Xe driver assertion in `nixos-hardware` requires kernel ≥ 6.8 | Not applicable | This spec does not import nixos-hardware; the assertion is irrelevant. The comment in the module warns users that xe requires ≥ 6.8, which the CachyOS kernel satisfies. |
| `vexos-intel` dry-build may fail on the CI host if `/etc/nixos/hardware-configuration.nix` is not present | Medium | This is expected behavior. The preflight script and dry-build must be run on a system that has `/etc/nixos/hardware-configuration.nix` present (as all builds require it). On a machine without Intel hardware, `nix flake check` will still pass because NixOS doesn't evaluate hardware-configuration.nix during `flake check`. |

---

## 10. Configuration Notes

### Verifying GuC / HuC after boot
```bash
dmesg | grep -i -e 'huc' -e 'guc'
# Expected output (i915 with enable_guc=3):
# i915 0000:00:02.0: [drm] GuC firmware ... submission:enabled
# i915 0000:00:02.0: [drm] HuC firmware ... authenticated:yes
```

### Verifying VA-API
```bash
vainfo
# Expected: iHD driver, with VAProfiles for H264, HEVC, VP9, AV1 (Arc/Xe)
```

### Verifying OpenCL
```bash
nix-shell -p clinfo --run clinfo
# Expected: Intel NEO OpenCL platform listed
```

### Alder Lake / 12th gen force probe (if X fails to start)
If the display server fails to start on Alder Lake (12th gen), the device ID may need to be forced:
```nix
# Add to hosts/intel.nix networking or a local overlay — NOT to modules/gpu/intel.nix
boot.kernelParams = [ "i915.force_probe=<device_id>" ];
# Get device ID: nix-shell -p pciutils --run "lspci -nn | grep VGA"
```

---

## 11. Summary

Three files require changes to add `vexos-intel`:

1. **New:** `modules/gpu/intel.nix` — i915 initrd KMS, GuC/HuC, iHD VA-API env var, `vpl-gpu-rt` (QSV), `intel-compute-runtime` (OpenCL), 32-bit iHD, `intel-gpu-tools`
2. **New:** `hosts/intel.nix` — thin host file importing `configuration.nix` + `modules/gpu/intel.nix`
3. **Modified:** `flake.nix` — add `vexos-intel` nixosConfiguration and `gpuIntel` nixosModule export

All required packages (`vpl-gpu-rt`, `intel-compute-runtime`, `intel-gpu-tools`) are confirmed present in nixpkgs 25.11. No new flake inputs are needed. `hardware.graphics.enable`, `enable32Bit`, `intel-media-driver`, and Mesa (ANV Vulkan) are already provided by the shared `modules/gpu.nix` base and require no duplication.
