# modules/gpu/nvidia.nix
# NVIDIA proprietary drivers with multi-generation support.
# Import this in hosts/nvidia.nix — do NOT use alongside gpu/amd.nix or gpu/vm.nix.
#
# Set vexos.gpu.nvidiaDriverVariant in your host config to match your GPU generation:
#   "latest"     — Turing (RTX 20xx / GTX 16xx) and newer  [default]
#   "legacy_535" — Maxwell / Pascal / Volta (GTX 750–1080 Ti, Titan V)
#   "legacy_470" — Kepler (GeForce 600 / 700 series)
#   "legacy_390" — Fermi  (GeForce 400 / 500 series)
{ config, pkgs, lib, ... }:

let
  variant = config.vexos.gpu.nvidiaDriverVariant;

  # Map variant string to the correct driver package.
  driverPackage =
    if variant == "latest"          then config.boot.kernelPackages.nvidiaPackages.stable
    else if variant == "legacy_535" then config.boot.kernelPackages.nvidiaPackages.legacy_535
    else if variant == "legacy_470" then config.boot.kernelPackages.nvidiaPackages.legacy_470
    else if variant == "legacy_390" then config.boot.kernelPackages.nvidiaPackages.legacy_390
    else abort "vexos.gpu.nvidiaDriverVariant: unknown value '${variant}'";

  # Open kernel modules require Turing (RTX 20xx / GTX 16xx) or newer.
  # All legacy variants must use proprietary closed modules.
  useOpen = variant == "latest";

in
{
  options.vexos.gpu.nvidiaDriverVariant = lib.mkOption {
    type = lib.types.enum [ "latest" "legacy_535" "legacy_470" "legacy_390" ];
    default = "latest";
    description = ''
      NVIDIA driver branch to use. Choose based on your GPU generation:

        "latest"     — stable (570.x) branch; open kernel modules for Turing (RTX 20xx / GTX 16xx+).
                       This is the correct choice for all RTX 20/30/40 series and GTX 16xx cards.
        "legacy_535" — 535.x LTS branch; proprietary modules required.
                       Use for Maxwell (GTX 750/Ti), Pascal (GTX 1050–1080 Ti), and Volta (Titan V).
        "legacy_470" — 470.x branch; proprietary modules required.
                       Use for Kepler GPUs: GeForce 600 and 700 series.
        "legacy_390" — 390.x branch; proprietary modules required.
                       Use for Fermi GPUs: GeForce 400 and 500 series.
    '';
  };

  config = {
    services.xserver.videoDrivers = [ "nvidia" ];

    hardware.nvidia = {
      # Open kernel modules: supported only on Turing (RTX 20xx / GTX 16xx) and newer.
      # All legacy variants must use proprietary closed modules (open = false).
      open = useOpen;

      # KMS: required for Wayland and reliable suspend/resume on all variants.
      modesetting.enable = true;

      powerManagement = {
        enable = false;       # set true if suspend/resume causes GPU lockups
        finegrained = false;  # set true for PRIME Turing+ discrete laptops only
      };

      package = driverPackage;
    };

    # nvidia-vaapi-driver provides VA-API via NVDEC.
    # NVDEC support is present only on Turing (RTX 20xx) and newer.
    # Excluded for all legacy variants to avoid broken hardware acceleration.
    hardware.graphics.extraPackages = lib.mkIf useOpen (
      with pkgs; [ nvidia-vaapi-driver ]
    );
  };
}
