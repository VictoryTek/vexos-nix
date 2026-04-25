# home-htpc.nix
# Home Manager configuration for user "nimda" — HTPC role.
# Manages HTPC-specific wallpapers, GNOME dconf wallpaper settings, and media-centre defaults.
{ config, pkgs, lib, inputs, ... }:
{
  imports = [ ./home/gnome-common.nix ];

  home.username    = "nimda";
  home.homeDirectory = "/home/nimda";

  # ── Shell ──────────────────────────────────────────────────────────────────
  programs.bash = {
    enable = true;
    shellAliases = {
      ll  = "ls -la";
      ".." = "cd ..";

      # Tailscale shortcuts
      ts   = "tailscale";
      tss  = "tailscale status";
      tsip = "tailscale ip";

      # System service shortcuts
      sshstatus = "systemctl status sshd";
      smbstatus = "systemctl status smbd";
    };
  };

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

  dconf.settings = {
    "org/gnome/shell" = {
      enabled-extensions = [
        "appindicatorsupport@rgcjonas.gmail.com"
        "dash-to-dock@micxgx.gmail.com"
        "AlphabeticalAppGrid@stuarthayhurst"
        # gamemode-shell-extension omitted — programs.gamemode not enabled on htpc
        "gnome-ui-tune@itstime.tech"
        "nothing-to-say@extensions.gnome.wouter.bolsterl.ee"
        "steal-my-focus-window@steal-my-focus-window"
        "tailscale-status@maxgallup.github.com"
        "caffeine@patapon.info"
        "restartto@tiagoporsch.github.io"
        "blur-my-shell@aunetx"
        "background-logo@fedorahosted.org"
      ];
      favorite-apps = [
        "brave-browser.desktop"
        "app.zen_browser.zen.desktop"
        "plex-desktop.desktop"
        "io.freetubeapp.FreeTube.desktop"
        "org.gnome.Nautilus.desktop"
        "io.github.up.desktop"
        "com.mitchellh.ghostty.desktop"
        "system-update.desktop"
      ];
    };

    "org/gnome/settings-daemon/plugins/power" = {
      sleep-inactive-ac-type      = "nothing";
      sleep-inactive-battery-type = "nothing";
    };

    "org/gnome/desktop/app-folders" = {
      folder-children = [ "Office" "Utilities" "System" ];
    };

    "org/gnome/desktop/app-folders/folders/Office" = {
      name = "Office";
      apps = [
        "org.gnome.TextEditor.desktop"
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
        "org.gnome.World.PikaBackup.desktop"
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
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
      accent-color = "orange";
    };  };

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
