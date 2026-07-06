# modules/gpu/nvidia.nix
# NVIDIA proprietary drivers with multi-generation support.
# Import this in hosts/nvidia.nix — do NOT use alongside gpu/amd.nix or gpu/vm.nix.
#
# Set vexos.gpu.nvidiaDriverVariant in your host config to select a driver branch:
#   "latest"     — Stable (580.x+) branch; open kernel modules; supports Maxwell (GTX 750+)
#                  through Ada/Hopper/Blackwell. Correct choice for GTX 750+, RTX 20/30/40/50xx and newer.
#   "legacy_535" — 535.x LTS branch; proprietary modules; open = false.
#                  Optional LTS alternative for Maxwell/Pascal/Volta. NOT architecturally required.
#   (legacy_470 / Kepler is no longer offered — dropped upstream by NVIDIA and Bazzite)
#   (legacy_390 / Fermi is broken in current nixpkgs and has been removed)
{ config, pkgs, lib, ... }:

let
  variant = config.vexos.gpu.nvidiaDriverVariant;

  # Map variant string to the correct driver package.
  driverPackage =
    if variant == "latest" then config.boot.kernelPackages.nvidiaPackages.stable
    else                        config.boot.kernelPackages.nvidiaPackages.legacy_535;

  # Open kernel modules require Turing (RTX 20xx / GTX 16xx) or newer.
  # legacy_535 must use proprietary closed modules.
  useOpen = variant == "latest";

in
{
  options.vexos.gpu.nvidiaDriverVariant = lib.mkOption {
    type = lib.types.enum [ "latest" "legacy_535" ];
    default = "latest";
    description = ''
      NVIDIA driver branch to use. Choose based on your GPU generation:

        "latest"     — stable (580.x+) branch; open kernel modules for Turing (RTX 20xx / GTX 16xx+) and newer.
                       This is the correct choice for all RTX 20/30/40/50 series and GTX 16xx cards.
        "legacy_535" — 535.x LTS branch; proprietary modules; open = false.
                       Optional stable alternative for Maxwell (GTX 750+), Pascal (GTX 1050–1080 Ti),
                       and Volta (Titan V) who prefer a proven LTS driver over current production.
                       These GPUs work equally well with "latest"; this variant is NOT required.
                       (Note: legacy_580 support is planned once nixpkgs issue #503740 is resolved)
    '';
  };

  config = {
    # NVIDIA proprietary drivers require explicit license acceptance.
    nixpkgs.config.nvidia.acceptLicense = true;

    services.xserver.videoDrivers = [ "nvidia" ];

    hardware.nvidia = {
      # Open kernel modules: supported only on Turing (RTX 20xx / GTX 16xx) and newer.
      # legacy_535 must use proprietary closed modules (open = false).
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
    # Installed unconditionally: legacy_535 is a driver-branch preference (LTS
    # vs. current production), not a GPU-generation boundary — NVIDIA's 535
    # branch supports Turing/Ampere/Ada too, so a legacy_535 user can have
    # full NVDEC hardware. On hardware that genuinely lacks NVDEC (older than
    # Turing), the driver falls back to software decode rather than breaking.
    hardware.graphics.extraPackages = with pkgs; [ nvidia-vaapi-driver ];

    # Prevent hardware-configuration.nix (generated inside a VM) from enabling
    # VirtualBox guest additions on bare-metal hosts. Guest additions fail to
    # build against linuxPackages_latest (kernel 6.12+).
    virtualisation.virtualbox.guest.enable = lib.mkForce false;
  };
}
