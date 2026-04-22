# modules/gpu-gaming.nix
# 32-bit GPU libraries (Steam/Proton) and gaming diagnostic tools.
# Sets hardware.graphics.enable32Bit = true unconditionally.
#
# Import in any configuration that runs Steam or Proton.
# Do NOT import on VM guests or headless roles.
{ pkgs, ... }:
{
  hardware.graphics.enable32Bit = true;

  # 32-bit VA-API and Mesa — required for Steam/Proton 32-bit graphics paths.
  hardware.graphics.extraPackages32 = with pkgs.pkgsi686Linux; [
    libva
    libva-vdpau-driver
    mesa
  ];

  environment.systemPackages = with pkgs; [
    vulkan-tools  # vulkaninfo — verify Vulkan driver and capabilities
    mesa-demos    # glxinfo, glxgears — OpenGL/Vulkan renderer diagnostics
  ];
}
