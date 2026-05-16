# modules/gnome-stateless.nix
# Stateless-only GNOME additions: teal accent, stateless dock favourites, and
# the Flatpak install service for the stateless role (TextEditor, Loupe). mpv
# is the video player (nixpkgs, via packages-desktop.nix).
{ config, pkgs, lib, ... }:
{
  imports = [ ./gnome.nix ];

  # ── Role-specific dconf overlay ───────────────────────────────────────────
  programs.dconf.profiles.user.databases = [
    {
      settings = {
        "org/gnome/desktop/interface" = {
          accent-color = "teal";
        };

        "org/gnome/shell" = {
          enabled-extensions = config.vexos.gnome.commonExtensions;
          favorite-apps = [
            "brave-browser.desktop"
            "torbrowser.desktop"
            "app.zen_browser.zen.desktop"
            "org.gnome.Nautilus.desktop"
            "com.mitchellh.ghostty.desktop"
            "io.github.up.desktop"
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
            "org.onlyoffice.desktopeditors.desktop"
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
          ];
        };

        "org/gnome/desktop/app-folders/folders/System" = {
          name = "System";
          apps = [
            "org.pulseaudio.pavucontrol.desktop"
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

  # ── GNOME default app Flatpaks (stateless role) ───────────────────────────
  vexos.gnome.flatpakInstall.apps = [
    "org.gnome.TextEditor"
    "org.gnome.Loupe"
  ];
}
