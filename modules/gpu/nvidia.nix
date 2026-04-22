# modules/gpu/nvidia.nix
# NVIDIA proprietary drivers with multi-generation support.
# Import this in hosts/nvidia.nix — do NOT use alongside gpu/amd.nix or gpu/vm.nix.
#
# Set vexos.gpu.nvidiaDriverVariant in your host config to select a driver branch:
#   "latest"     — Stable (580.x+) branch; open kernel modules; supports Maxwell (GTX 750+)
#                  through Ada/Hopper/Blackwell. Correct choice for GTX 750+, RTX 20/30/40/50xx and newer.
#   "legacy_535" — 535.x LTS branch; proprietary modules; open = false.
#                  Optional LTS alternative for Maxwell/Pascal/Volta. NOT architecturally required.
#   "legacy_470" — Kepler (GeForce 600 / 700 series)
#   (legacy_390 / Fermi is broken in current nixpkgs and has been removed)
{ config, pkgs, lib, ... }:

let
  variant = config.vexos.gpu.nvidiaDriverVariant;

  # Map variant string to the correct driver package.
  driverPackage =
    if variant == "latest"          then config.boot.kernelPackages.nvidiaPackages.stable
    else if variant == "legacy_535" then config.boot.kernelPackages.nvidiaPackages.legacy_535
    else if variant == "legacy_470" then config.boot.kernelPackages.nvidiaPackages.legacy_470
    else abort "vexos.gpu.nvidiaDriverVariant: unknown value '${variant}'";  # legacy_390 (Fermi) is broken in nixpkgs

  # Open kernel modules require Turing (RTX 20xx / GTX 16xx) or newer.
  # All legacy variants must use proprietary closed modules.
  useOpen = variant == "latest";

in
{
  options.vexos.gpu.nvidiaDriverVariant = lib.mkOption {
    type = lib.types.enum [ "latest" "legacy_535" "legacy_470" ];
    default = "latest";
    description = ''
      NVIDIA driver branch to use. Choose based on your GPU generation:

        "latest"     — stable (580.x+) branch; open kernel modules for Turing (RTX 20xx / GTX 16xx+) and newer.
                       This is the correct choice for all RTX 20/30/40/50 series and GTX 16xx cards.
        "legacy_535" — 535.x LTS branch; proprietary modules; open = false.
                       Optional stable alternative for Maxwell (GTX 750+), Pascal (GTX 1050–1080 Ti),
                       and Volta (Titan V) who prefer a proven LTS driver over current production.
                       These GPUs work equally well with "latest"; this variant is NOT required.
        "legacy_470" — 470.x branch; proprietary modules required.
                       Use for Kepler GPUs: GeForce 600 and 700 series.
                       (legacy_390 / Fermi is broken in current nixpkgs and is not supported)
    '';
  };

  config = {
    # NVIDIA proprietary drivers require explicit license acceptance.
    nixpkgs.config.nvidia.acceptLicense = true;

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
