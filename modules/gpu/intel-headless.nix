# modules/gpu/intel-headless.nix
# Intel GPU for headless server roles: QSV/OpenCL compute without the early-KMS
# initrd load (i915) from modules/gpu/intel.nix.
#
# i915 loads normally during kernel boot — initrd early load is only beneficial
# on display roles where it sets the correct framebuffer from the boot splash.
# On a headless server, early i915 KMS leaves the console on a blank DRM surface
# (black screen + blinking cursor) with no display manager to take it over.
#
# GuC/HuC firmware loading (i915.enable_guc=3) is retained — it is required for
# Quick Sync Video (QSV) hardware transcoding regardless of display presence.
#
# For Intel Arc B-series (Battlemage), Meteor Lake, or Lunar Lake:
#   Replace boot.kernelParams i915.enable_guc=3 with the xe driver equivalent.
{ pkgs, lib, ... }:
{
  # GuC submission + HuC firmware loading — required for QSV transcoding
  boot.kernelParams = [ "i915.enable_guc=3" ];

  # Required for GuC/HuC firmware blobs (i915/<gpu>_guc_*.bin, i915/<gpu>_huc_*.bin)
  hardware.enableRedistributableFirmware = true;

  # Prefer the modern iHD VA-API backend (intel-media-driver, Broadwell 2014+)
  environment.sessionVariables = {
    LIBVA_DRIVER_NAME = "iHD";
  };

  # Intel-specific graphics acceleration packages
  hardware.graphics.extraPackages = with pkgs; [
    vpl-gpu-rt              # Intel oneVPL: Quick Sync Video hardware encode/decode (Gen12+)
    intel-compute-runtime   # OpenCL NEO + Level Zero: GPU compute on Arc/Xe/12th gen+
  ];

  # Prevent hardware-configuration.nix (generated inside a VM) from enabling
  # VirtualBox guest additions on bare-metal hosts. Guest additions fail to
  # build against linuxPackages_latest (kernel 6.12+).
  virtualisation.virtualbox.guest.enable = lib.mkForce false;
}
