# modules/gpu/nvidia.nix
# NVIDIA proprietary drivers with multi-generation support.
# Import this in hosts/nvidia.nix — do NOT use alongside gpu/amd.nix or gpu/vm.nix.
#
# Set vexos.gpu.nvidiaDriverVariant in your host config to select a driver branch:
#   "latest"     — Production (595.x) branch; open kernel modules; Turing (RTX 20xx /
#                  GTX 16xx) through Ada/Hopper/Blackwell.
#   "legacy_580" — 580.x branch; proprietary modules; open = false.
#                  REQUIRED for Maxwell (GTX 750+), Pascal (GTX 10xx, Quadro P-series)
#                  and Volta — 580 is the last NVIDIA branch supporting them, and the
#                  open modules need Turing+, so those GPUs cannot use "latest" at all.
#   (legacy_535 / 535.x was removed — it does not build on any kernel this project
#    ships (verified against 6.12, 7.1 and 7.2), and legacy_580 supersedes it for the
#    same hardware)
#   (legacy_470 / Kepler is no longer offered — dropped upstream by NVIDIA and Bazzite)
#   (legacy_390 / Fermi is broken in current nixpkgs and has been removed)
{ config, pkgs, lib, ... }:

let
  variant = config.vexos.gpu.nvidiaDriverVariant;

  stable = config.boot.kernelPackages.nvidiaPackages.stable;

  # Map variant string to the correct driver package.
  #
  # Neither variant needs a kernel-compat patch: "latest" (595.112.07+) and
  # legacy_580 (580.178.04+) both build on Linux 7.x as shipped. (A vendored
  # CachyOS 7.2 patch for 595.71.05 was removed — 595.112.07 already contains
  # those fixes, so the patch no longer applies. Likewise the earlier strncpy
  # patch for 580.173.02.)
  driverPackage =
    if variant == "latest" then
      stable
    else
      config.boot.kernelPackages.nvidiaPackages.legacy_580;

  # Open kernel modules require Turing (RTX 20xx / GTX 16xx) or newer.
  # legacy_580 targets Maxwell/Pascal/Volta and must use proprietary closed modules.
  useOpen = variant == "latest";

in
{
  options.vexos.gpu.nvidiaDriverVariant = lib.mkOption {
    type = lib.types.enum [ "latest" "legacy_580" ];
    default = "latest";
    description = ''
      NVIDIA driver branch to use. Choose based on your GPU generation:

        "latest"     — production (595.x) branch; open kernel modules.
                       Turing (RTX 20xx / GTX 16xx) and newer only.
                       Correct choice for all RTX 20/30/40/50 series and GTX 16xx cards.
        "legacy_580" — 580.x branch; proprietary modules; open = false.
                       REQUIRED for Maxwell (GTX 750+), Pascal (GTX 10xx,
                       Quadro P-series) and Volta (Titan V). NVIDIA's 580 branch
                       is the last to support these architectures — 590 and newer
                       dropped them — and the open kernel modules used by "latest"
                       require Turing or newer, so these GPUs cannot run "latest".
                       The 580.x closed modules build on Linux 7.2 unpatched, so
                       this variant tracks the role's normal kernel like every
                       other GPU.
    '';
  };

  config = {
    # NVIDIA proprietary drivers require explicit license acceptance.
    nixpkgs.config.nvidia.acceptLicense = true;

    services.xserver.videoDrivers = [ "nvidia" ];

    hardware.nvidia = {
      # Open kernel modules: supported only on Turing (RTX 20xx / GTX 16xx) and newer.
      # legacy_580 must use proprietary closed modules (open = false).
      open = useOpen;

      # KMS: required for Wayland and reliable suspend/resume on all variants.
      modesetting.enable = true;

      powerManagement = {
        enable = false;       # set true if suspend/resume causes GPU lockups
        finegrained = false;  # set true for PRIME Turing+ discrete laptops only
      };

      package = driverPackage;
    };

    # nvidia-vaapi-driver provides VA-API via NVDEC (Turing/RTX 20xx and newer).
    # Installed unconditionally: on Maxwell/Pascal/Volta hardware (legacy_580),
    # which genuinely lacks NVDEC, the driver falls back to software decode
    # rather than breaking.
    hardware.graphics.extraPackages = with pkgs; [ nvidia-vaapi-driver ];

    # Prevent hardware-configuration.nix (generated inside a VM) from enabling
    # VirtualBox guest additions on bare-metal hosts. Guest additions fail to
    # build against linuxPackages_latest (kernel 6.12+).
    virtualisation.virtualbox.guest.enable = lib.mkForce false;
  };
}
