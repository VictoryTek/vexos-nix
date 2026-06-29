# modules/gnome-desktop.nix
# Desktop-only GNOME additions: GameMode shell extension, blue accent,
# desktop favourites, and the Flatpak install service for the desktop role
# (TextEditor, Loupe, Calculator, Calendar, Papers, Snapshot). mpv is the
# video player (nixpkgs, via packages-desktop.nix).
{ config, pkgs, lib, ... }:
{
  imports = [ ./gnome.nix ];

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
            config.vexos.gnome.commonExtensions ++ config.vexos.gnome.extraExtensions;
          favorite-apps = [
            "brave-browser.desktop"
            "app.zen_browser.zen.desktop"
            "org.gnome.Nautilus.desktop"
            "com.mitchellh.ghostty.desktop"
            "io.github.up.desktop"
            "org.gnome.Boxes.desktop"
            "codium.desktop"
          ];
        };

        "org/gnome/shell/extensions/dash-to-dock" = {
          dock-position = "LEFT";
          autohide      = true;
          intellihide   = true;
        };

        # ── Mic mute global keybinding ──────────────────────────────────
        # gsd-media-keys runs a flock-debounced wrapper so key-autorepeat
        # events hit a locked fd and exit; only one wpctl call fires per
        # physical keypress.  canberra-gtk-play gives XDG sound feedback.
        "org/gnome/settings-daemon/plugins/media-keys" = {
          custom-keybindings = [ "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/mute-mic/" ];
        };
        "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/mute-mic" = {
          name    = "Toggle microphone mute";
          binding = "<Super>backslash";
          command = toString (pkgs.writeShellScript "toggle-mic" ''
            (
              flock -n 9 || exit 0
              ${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle
              if ${pkgs.wireplumber}/bin/wpctl get-volume @DEFAULT_AUDIO_SOURCE@ \
                  | grep -q MUTED; then
                ${pkgs.pipewire}/bin/pw-play \
                  ${pkgs.sound-theme-freedesktop}/share/sounds/freedesktop/stereo/device-removed.oga
              else
                ${pkgs.pipewire}/bin/pw-play \
                  ${pkgs.sound-theme-freedesktop}/share/sounds/freedesktop/stereo/device-added.oga
              fi
              sleep 0.3
            ) 9>"''${XDG_RUNTIME_DIR}/mic-toggle.lock"
          '');
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
            "net.cozic.joplin_desktop.desktop"
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
            "LocalSend.desktop"
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

  # ── Mic mute on login ─────────────────────────────────────────────────────
  # Ensures the microphone starts muted at every graphical session start.
  # The user unmutes with <Super>backslash (nothing-to-say extension).
  systemd.user.services.mute-mic-on-login = {
    description = "Mute microphone at graphical session start";
    wantedBy    = [ "graphical-session.target" ];
    after       = [ "graphical-session.target" ];
    serviceConfig = {
      Type      = "oneshot";
      ExecStart = "${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SOURCE@ 1";
    };
  };

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
