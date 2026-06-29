# modules/gpu/amd.nix
# AMD GPU: amdgpu initrd early load, RADV Vulkan, ROCm/OpenCL, LACT.
# Import this in hosts/amd.nix — do NOT use alongside gpu/nvidia.nix or gpu/vm.nix.
{ config, pkgs, lib, ... }:
{
  # Load amdgpu kernel module early for better boot resolution and GPU init
  boot.initrd.kernelModules = [ "amdgpu" ];

  # Force RADV over AMDVLK (RADV is actively maintained and faster for gaming)
  environment.variables.AMD_VULKAN_ICD = "RADV";

  # ROCm OpenCL runtime (GPU compute: Blender, AI tools, etc.)
  hardware.graphics.extraPackages = with pkgs; [
    rocmPackages.clr      # ROCm Common Language Runtime
    rocmPackages.clr.icd  # OpenCL ICD registration
  ];

  # LACT — GPU overclocking, fan curves, and power profiles (matches Bazzite)
  services.lact.enable = true;

  # GameMode AMD GPU boost: switch amdgpu power_dpm_force_performance_level to
  # "high" while a game is active. Only applies when gaming feature is enabled.
  programs.gamemode.settings.gpu = lib.mkIf config.vexos.features.gaming.enable {
    apply_gpu_optimisations = "accept-responsibility";
    gpu_device = 0;
    amd_performance_level = "high";
  };

  # RADV Graphics Pipeline Libraries: enables async Vulkan pipeline compilation,
  # reducing first-play stutter. Safe no-op if Mesa has already promoted gpl to default.
  environment.variables.RADV_PERFTEST = "gpl";

  # ROCm device node symlink: many compute apps hard-code /opt/rocm
  systemd.tmpfiles.rules =
    let
      rocmEnv = pkgs.symlinkJoin {
        name = "rocm-combined";
        paths = with pkgs.rocmPackages; [ rocblas hipblas clr ];
      };
    in [
      "L+  /opt/rocm  -  -  -  -  ${rocmEnv}"
    ];

  # Prevent hardware-configuration.nix (generated inside a VM) from enabling
  # VirtualBox guest additions on bare-metal hosts. Guest additions fail to
  # build against linuxPackages_latest (kernel 6.12+).
  virtualisation.virtualbox.guest.enable = lib.mkForce false;
}
