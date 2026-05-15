# modules/gnome-htpc.nix
# HTPC-only GNOME additions: orange accent, htpc dock favourites, and the
# Flatpak install service for the htpc role (TextEditor, Loupe — no Totem,
# mpv is the designated player here).
{ config, pkgs, lib, ... }:
let
  # Common shell extensions enabled on every role.
  commonExtensions = [
    "appindicatorsupport@rgcjonas.gmail.com"
    "dash-to-dock@micxgx.gmail.com"
    "AlphabeticalAppGrid@stuarthayhurst"
    "gnome-ui-tune@itstime.tech"
    "nothing-to-say@extensions.gnome.wouter.bolsterl.ee"
    "steal-my-focus-window@steal-my-focus-window"
    "tailscale-status@maxgallup.github.com"
    "caffeine@patapon.info"
    "restartto@tiagoporsch.github.io"
    "blur-my-shell@aunetx"
    "background-logo@fedorahosted.org"
    "tiling-assistant@leleat-on-github"
  ];
in
{
  imports = [ ./gnome.nix ];

  # ── Role-specific dconf overlay ───────────────────────────────────────────
  programs.dconf.profiles.user.databases = [
    {
      settings = {
        "org/gnome/desktop/interface" = {
          accent-color = "orange";
        };

        "org/gnome/shell" = {
          enabled-extensions = commonExtensions;
          favorite-apps = [
            "brave-browser.desktop"
            "app.zen_browser.zen.desktop"
            "plex-desktop.desktop"             # nixpkgs plex-desktop package
            "io.freetubeapp.FreeTube.desktop"
            "org.gnome.Nautilus.desktop"
            "io.github.up.desktop"
            "com.mitchellh.ghostty.desktop"
          ];
        };

        "org/gnome/shell/extensions/dash-to-dock" = {
          dock-position = "LEFT";
          autohide      = true;
          intellihide   = true;
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
            "gparted.desktop"
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
    }
  ];

  # ── GNOME default app Flatpaks (htpc role) ────────────────────────────────
  vexos.gnome.flatpakInstall.apps = [
    "org.gnome.TextEditor"
    "org.gnome.Loupe"
  ];
}
