# modules/3d-print.nix
# Desktop-role 3D printing Flatpak additions: Blender and OrcaSlicer.
#
# Enable on a per-host basis via /etc/nixos/features.nix:
#   vexos.features.print3d.enable = true;
# Requires: modules/flatpak.nix (declares vexos.flatpak.extraApps option).
{ config, lib, ... }:
let
  cfg = config.vexos.features.print3d;
in
{
  options.vexos.features.print3d.enable = lib.mkEnableOption "3D printing tools (Blender, OrcaSlicer via Flatpak)";

  config = lib.mkIf cfg.enable {
    vexos.flatpak.extraApps = [
      "org.blender.Blender"       # 3D modelling, sculpting, rendering, animation
      "com.orcaslicer.OrcaSlicer" # FDM slicer with multi-material and plate support
    ];
  };
}
