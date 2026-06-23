# modules/3d-print.nix
# Desktop-role 3D printing additions: Blender, OrcaSlicer, and Creality Print.
#
# Import only in configuration-desktop.nix.
# Requires: modules/flatpak.nix (declares vexos.flatpak.extraApps option).
{ pkgs, ... }:
{
  vexos.flatpak.extraApps = [
    "org.blender.Blender"       # 3D modelling, sculpting, rendering, animation
    "com.orcaslicer.OrcaSlicer" # FDM slicer with multi-material and plate support
  ];

  environment.systemPackages = [
    pkgs.vexos.creality-print   # Creality's official slicer (AppImage, unfree)
  ];
}
