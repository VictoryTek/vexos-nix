# modules/gpu/nvidia.nix
# NVIDIA proprietary drivers: open kernel modules (Turing/RTX+), modesetting, VA-API.
# Import this in hosts/nvidia.nix — do NOT use alongside gpu/amd.nix or gpu/vm.nix.
#
# IMPORTANT: Set hardware.nvidia.open = false for Maxwell/Pascal/Volta (GTX 900–1000/Titan V).
{ config, pkgs, lib, ... }:
{
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    # Open kernel modules: required for Turing (RTX 20+) and GTX 16+ for Wayland.
    # Set to false for Maxwell/Pascal/Volta GPUs.
    open = true;

    # KMS: required for Wayland and reliable suspend/resume
    modesetting.enable = true;

    powerManagement = {
      enable = false;       # set true if suspend/resume causes GPU lockups
      finegrained = false;  # set true for PRIME Turing+ discrete laptops
    };

    # Stable driver branch — change to beta or production if needed
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  # NVIDIA VA-API driver (hardware video decode via nvdec)
  hardware.graphics.extraPackages = with pkgs; [
    nvidia-vaapi-driver
  ];
}
