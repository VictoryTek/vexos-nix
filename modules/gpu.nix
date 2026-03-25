# modules/gpu.nix
# Common GPU base: hardware.graphics, VA-API/VDPAU, Vulkan and codec tools.
# GPU-brand-specific configuration lives in modules/gpu/{amd,nvidia,vm}.nix
# and is imported by the host config in hosts/{amd,nvidia,vm}.nix.
{ config, pkgs, lib, ... }:
{
  # ── Common graphics ───────────────────────────────────────────────────────
  hardware.graphics = {
    enable = true;
    enable32Bit = true; # required for Steam/Proton 32-bit applications

    # Base VA-API and VDPAU acceleration packages (all builds)
    extraPackages = with pkgs; [
      libva               # VA-API runtime
      libva-vdpau-driver  # VDPAU via VA-API bridge (renamed from vaapiVdpau)
      libvdpau-va-gl      # VDPAU OpenGL backend
      intel-media-driver  # iHD VA-API driver (Intel 8th gen+); harmless on AMD/NVIDIA
      mesa                # includes RADV (AMD Vulkan) and llvmpipe
    ];

    extraPackages32 = with pkgs.pkgsi686Linux; [
      libva
      libva-vdpau-driver
      mesa
    ];
  };

  # ── Video codec and Vulkan utilities ──────────────────────────────────────
  environment.systemPackages = with pkgs; [
    ffmpeg-full  # full codec support: H264, HEVC, AV1, VP9, etc.
    libva-utils  # vainfo — verify VA-API acceleration
    vulkan-tools # vulkaninfo
    vulkan-loader
    glxinfo      # OpenGL / Vulkan renderer info
  ];
}
