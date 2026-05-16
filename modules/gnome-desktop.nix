# modules/gnome-desktop.nix
# Desktop-only GNOME additions: GameMode shell extension, blue accent,
# desktop favourites, and the Flatpak install service for the desktop role
# (TextEditor, Loupe, Calculator, Calendar, Papers, Snapshot). mpv is the
# video player (nixpkgs, via packages-desktop.nix).
{ config, pkgs, lib, ... }:
{
  imports = [ ./gnome.nix ];

  # ── Desktop-only GNOME Shell extension package ────────────────────────────
  environment.systemPackages = with pkgs; [
    unstable.gnomeExtensions.gamemode-shell-extension   # GameMode status indicator
  ];

  # ── Role-specific dconf overlay ───────────────────────────────────────────
  # Adds accent-color, enabled-extensions, and favorite-apps to the
  # system dconf user database.  Lists concatenate with the universal
  # database defined in ./gnome.nix; the keys here do not overlap.
  programs.dconf.profiles.user.databases = [
    {
      settings = {
        "org/gnome/desktop/interface" = {
          accent-color = "blue";
        };

        "org/gnome/shell" = {
          enabled-extensions =
            config.vexos.gnome.commonExtensions ++ [ "gamemodeshellextension@trsnaqe.com" ];
          favorite-apps = [
            "brave-browser.desktop"
            "app.zen_browser.zen.desktop"
            "org.gnome.Nautilus.desktop"
            "com.mitchellh.ghostty.desktop"
            "io.github.up.desktop"
            "org.gnome.Boxes.desktop"
            "code.desktop"
          ];
        };

        "org/gnome/shell/extensions/dash-to-dock" = {
          dock-position = "LEFT";
          autohide      = true;
          intellihide   = true;
        };

        "org/gnome/desktop/app-folders" = {
          folder-children = [ "Games" "Game Utilities" "Office" "Utilities" "System" ];
        };

        "org/gnome/desktop/app-folders/folders/Games" = {
          name = "Games";
          apps = [
            "org.prismlauncher.PrismLauncher.desktop"
            "net.lutris.Lutris.desktop"
            "steam.desktop"
            "com.hypixel.HytaleLauncher.desktop"
            "Ryujinx.desktop"
            "com.libretro.RetroArch.desktop"
          ];
        };

        "org/gnome/desktop/app-folders/folders/Game Utilities" = {
          name = "Game Utilities";
          apps = [
            "com.vysp3r.ProtonPlus.desktop"
            "protontricks.desktop"
            "vesktop.desktop"
            "discord.desktop"
          ];
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
            "com.system76.Popsicle.desktop"
          ];
        };
      };
    }
  ];

  # ── GNOME default app Flatpaks (desktop role) ─────────────────────────────
  # Defined by modules/gnome-flatpak-install.nix (imported via gnome.nix).
  # Note: stamp hash changes from the pre-migration value (extraRemoves adds
  # org.gnome.Totem to the hash string) — service re-runs once on next boot;
  # re-run is idempotent.
  vexos.gnome.flatpakInstall = {
    apps = [
      "org.gnome.TextEditor"
      "org.gnome.Loupe"
      "org.gnome.Calculator"
      "org.gnome.Calendar"
      "org.gnome.Papers"
      "org.gnome.Snapshot"
    ];
    extraRemoves = [ "org.gnome.Totem" ];
  };
}
