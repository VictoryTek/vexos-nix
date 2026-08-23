# modules/desktop-environment.nix
# Declares the desktop-role DE/compositor choice. Read by modules/gnome.nix,
# modules/gnome-desktop.nix, modules/cosmic-desktop.nix,
# modules/hyprland-desktop.nix, and modules/branding-display.nix to gate
# their GNOME/COSMIC/Hyprland-specific content. Set per-host, e.g. in
# /etc/nixos/features.nix:
#   vexos.desktop.environment = "cosmic";
{ lib, ... }:
{
  options.vexos.desktop.environment = lib.mkOption {
    type        = lib.types.enum [ "gnome" "cosmic" "hyprland" ];
    default     = "gnome";
    description = "Desktop environment/compositor used by the desktop role.";
  };
}
