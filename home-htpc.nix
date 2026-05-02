# home-htpc.nix
# Home Manager configuration for user "nimda" — HTPC role.
# Manages HTPC-specific wallpapers, GNOME dconf wallpaper settings, and media-centre defaults.
{ config, pkgs, lib, inputs, ... }:
{
  imports = [ ./home/bash-common.nix ./home/gnome-common.nix ];

  home.username    = "nimda";
  home.homeDirectory = "/home/nimda";

  # ── Starship prompt ────────────────────────────────────────────────────────
  programs.starship = {
    enable = true;
    enableBashIntegration = true;
  };

  xdg.configFile."starship.toml".source = ./files/starship.toml;

  # ── Wallpapers ─────────────────────────────────────────────────────────────
  # Copied from the repo into ~/Pictures/Wallpapers/ at each activation.
  home.file."Pictures/Wallpapers/vex-bb-light.jxl".source = ./wallpapers/htpc/vex-bb-light.jxl;
  home.file."Pictures/Wallpapers/vex-bb-dark.jxl".source  = ./wallpapers/htpc/vex-bb-dark.jxl;

  # ── GNOME dconf defaults ─────────────────────────────────────────────────
  # All dconf keys are set via the system dconf database in modules/gnome.nix
  # and modules/gnome-htpc.nix.  The system-db provides defaults; user changes
  # in GNOME Settings survive rebuilds because the user-db has higher priority.

  # ── Hidden app grid entries ────────────────────────────────────────────────
  # These packages cannot be safely removed (they are required dependencies),
  # so their .desktop files are masked to keep them out of the app grid.
  xdg.desktopEntries."org.gnome.Extensions" = {
    name      = "Extensions";
    noDisplay = true;
    settings.Hidden = "true";
  };
  # ── Justfile ───────────────────────────────────────────────────────────────
  # Deploy the repo's justfile to ~/justfile so 'just' works from home dir.
  home.file."justfile".source = ./justfile;

  home.stateVersion = "24.05";
}
