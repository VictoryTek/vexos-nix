# modules/3d-print.nix
# Desktop-role 3D printing Flatpak additions: Blender, OrcaSlicer and SolidCraft.
#
# Enable on a per-host basis via /etc/nixos/features.nix:
#   vexos.features.print3d.enable = true;
# Requires: modules/flatpak.nix (declares vexos.flatpak.extraApps option) and
# modules/flatpak-bundles.nix (declares vexos.flatpak.bundles, used for SolidCraft,
# which upstream ships only as a release-asset .flatpak).
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.features.print3d;
  solidcraft = pkgs.vexos.craft-apps.solidcraft;
in
{
  options.vexos.features.print3d.enable = lib.mkEnableOption "3D printing tools (Blender, OrcaSlicer, SolidCraft via Flatpak)";

  config = lib.mkMerge [
    { vexos.flatpak.managedApps = [
        "org.blender.Blender"
        "com.orcaslicer.OrcaSlicer"
        "ai.storyteller.solidcraft"  # pre-0.25 SolidCraft ID; removed on upgrade to io.tangencylabs.solidcraft
      ];
    }

    (lib.mkIf cfg.enable {
      vexos.flatpak.extraApps = [
        "org.blender.Blender"       # 3D modelling, sculpting, rendering, animation
        "com.orcaslicer.OrcaSlicer" # FDM slicer with multi-material and plate support
      ];

      vexos.flatpak.bundles = [
        { id = solidcraft.appId; inherit (solidcraft) version; src = solidcraft.bundle; }  # SolidCraft parametric CAD
      ];
    })
  ];
}
