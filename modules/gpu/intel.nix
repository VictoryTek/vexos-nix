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

  # Prevent hardware-configuration.nix (generated inside a VM) from enabling
  # VirtualBox guest additions on bare-metal hosts. Guest additions fail to
  # build against linuxPackages_latest (kernel 6.12+).
  virtualisation.virtualbox.guest.enable = lib.mkForce false;
}
