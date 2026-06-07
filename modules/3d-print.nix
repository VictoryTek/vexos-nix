# modules/3d-print.nix
# Desktop-role 3D printing Flatpak additions: Blender and OrcaSlicer.
#
# Import only in configuration-desktop.nix.
# Requires: modules/flatpak.nix (declares vexos.flatpak.extraApps option).
{ ... }:
{
  vexos.flatpak.extraApps = [
    "org.blender.Blender"       # 3D modelling, sculpting, rendering, animation
    "com.orcaslicer.OrcaSlicer" # FDM slicer with multi-material and plate support
  ];
}
