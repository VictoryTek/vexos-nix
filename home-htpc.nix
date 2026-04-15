# home-htpc.nix
# Home Manager configuration for user "nimda" — HTPC role.
# Manages HTPC-specific wallpapers, GNOME dconf wallpaper settings, and media-centre defaults.
{ config, pkgs, lib, inputs, ... }:
{
  home.username    = "nimda";
  home.homeDirectory = "/home/nimda";

  # ── Wallpapers ─────────────────────────────────────────────────────────────
  # Copied from the repo into ~/Pictures/Wallpapers/ at each activation.
  home.file."Pictures/Wallpapers/vex-bb-light.jxl".source = ./wallpapers/htpc/vex-bb-light.jxl;
  home.file."Pictures/Wallpapers/vex-bb-dark.jxl".source  = ./wallpapers/htpc/vex-bb-dark.jxl;

  dconf.settings = {
    "org/gnome/shell" = {
      favorite-apps = [
        "com.brave.Browser.desktop"
        "io.gitlab.librewolf-community.desktop"
        "tv.plex.PlexDesktop.desktop"
        "io.freetubeapp.FreeTube.desktop"
        "org.gnome.Nautilus.desktop"
        "com.mitchellh.ghostty.desktop"
        "system-update.desktop"
      ];
    };

    "org/gnome/desktop/background" = {
      picture-uri      = "file:///home/nimda/Pictures/Wallpapers/vex-bb-light.jxl";
      picture-uri-dark = "file:///home/nimda/Pictures/Wallpapers/vex-bb-dark.jxl";
      picture-options  = "zoom";
    };

    "org/gnome/settings-daemon/plugins/power" = {
      sleep-inactive-ac-type      = "nothing";
      sleep-inactive-battery-type = "nothing";
    };

    "org/gnome/desktop/screensaver" = {
      lock-enabled = false;
    };
  };

  home.stateVersion = "24.05";
}
