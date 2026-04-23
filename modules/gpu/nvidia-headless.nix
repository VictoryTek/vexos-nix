# modules/gpu/nvidia-headless.nix
# NVIDIA GPU for headless server roles.
# Inherits driver selection from modules/gpu/nvidia.nix but disables KMS
# modesetting, which is only required for Wayland display sessions (GDM/mutter).
# Disabling modesetting on headless avoids unnecessary DRM initialisation and
# prevents the nvidia-drm.modeset=1 kernel parameter from being set, which can
# leave the console in a blank framebuffer state with no compositor to take over.
{ lib, ... }:
{
  imports = [ ./nvidia.nix ];

  # KMS modesetting is required for Wayland output (GDM/mutter).
  # Disabled on headless servers — no display manager is running.
  hardware.nvidia.modesetting.enable = lib.mkForce false;
}
