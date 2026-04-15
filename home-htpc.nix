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
        "app.zen_browser.zen.desktop"
        "tv.plex.PlexDesktop.desktop"
        "io.freetubeapp.FreeTube.desktop"
        "org.gnome.Nautilus.desktop"
        "io.github.up.desktop"
        "com.mitchellh.ghostty.desktop"
        "system-update.desktop"
      ];
    };

    "org/gnome/desktop/interface" = {
      clock-format = "12h";
      cursor-size  = 24;
      cursor-theme = "Bibata-Modern-Classic";
      icon-theme   = "kora";
    };

    "org/gnome/desktop/wm/preferences" = {
      button-layout = "appmenu:minimize,maximize,close";
    };

    "org/gnome/desktop/background" = {
      picture-uri      = "file:///home/nimda/Pictures/Wallpapers/vex-bb-light.jxl";
      picture-uri-dark = "file:///home/nimda/Pictures/Wallpapers/vex-bb-dark.jxl";
      picture-options  = "zoom";
    };

    "org/gnome/shell/extensions/dash-to-dock" = {
      dock-position = "LEFT";
    };

    "org/fedorahosted/background-logo-extension" = {
      logo-file         = "/run/current-system/sw/share/pixmaps/vex-background-logo.svg";
      logo-file-dark    = "/run/current-system/sw/share/pixmaps/vex-background-logo-dark.svg";
      logo-always-visible = true;
    };

    "org/gnome/desktop/screensaver" = {
      lock-enabled = false;
      lock-delay   = lib.gvariant.mkUint32 0;
    };

    "org/gnome/session" = {
      idle-delay = lib.gvariant.mkUint32 300;  # 5 min inactivity
    };

    "org/gnome/settings-daemon/plugins/power" = {
      sleep-inactive-ac-type      = "nothing";
      sleep-inactive-battery-type = "nothing";
    };

    "org/gnome/desktop/screensaver" = {
      lock-enabled = false;
    };

    "org/gnome/desktop/app-folders" = {
      folder-children = [ "Office" "Utilities" "System" ];
    };

    "org/gnome/desktop/app-folders/folders/Office" = {
      name = "Office";
      apps = [
        "org.onlyoffice.desktopeditors.desktop"
        "org.gnome.TextEditor.desktop"
        "org.gnome.Papers.desktop"
      ];
    };

    "org/gnome/desktop/app-folders/folders/Utilities" = {
      name = "Utilities";
      apps = [
        "com.mattjakeman.ExtensionManager.desktop"
        "it.mijorus.gearlever.desktop"
        "org.gnome.tweaks.desktop"
        "io.github.flattool.Warehouse.desktop"
        "io.missioncenter.MissionCenter.desktop"
        "com.github.tchx84.Flatseal.desktop"
      ];
    };

    "org/gnome/desktop/app-folders/folders/System" = {
      name = "System";
      apps = [
        "org.pulseaudio.pavucontrol.desktop"
        "rog-control-center.desktop"
        "io.missioncenter.MissionCenter.desktop"
        "org.gnome.Settings.desktop"
        "org.gnome.seahorse.Application.desktop"
        "nixos-manual.desktop"
        "cups.desktop"
        "blivet-gui.desktop"
        "blueman-manager.desktop"
        "btop.desktop"
        "ca.desrt.dconf-editor.desktop"
        "org.gnome.baobab.desktop"
        "org.gnome.DiskUtility.desktop"
        "org.gnome.font-viewer.desktop"
        "org.gnome.Logs.desktop"
        "btrfs-assistant.desktop"
        "org.gnome.SystemMonitor.desktop"
      ];
    };
  };

  home.stateVersion = "24.05";
}
