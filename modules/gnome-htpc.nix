# modules/gnome-htpc.nix
# HTPC-only GNOME additions: orange accent, htpc dock favourites, and the
# Flatpak install service for the htpc role (TextEditor, Loupe — no Totem,
# mpv is the designated player here).
{ config, pkgs, lib, ... }:
let
  # Local app list for the systemd flatpak-install service.
  # HTPC excludes org.gnome.Totem entirely.
  gnomeAppsToInstall = [
    "org.gnome.TextEditor"
    "org.gnome.Loupe"
  ];

  gnomeAppsHash = builtins.substring 0 16
    (builtins.hashString "sha256" (lib.concatStringsSep "," gnomeAppsToInstall));

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
    "tiling-assistant@leleat-on.github.com"
  ];
in
{
  imports = [ ./gnome.nix ];

  # ── HTPC bloat reduction (in addition to the universal list) ──────────────
  environment.gnome.excludePackages = with pkgs; [
    papers            # Flatpak org.gnome.Papers installed on desktop only
  ];

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
      };
    }
  ];

  # ── GNOME default app Flatpaks (htpc role) ────────────────────────────────
  # Includes migration cleanup for both the desktop-only apps and Totem,
  # which may have been installed under previous configurations.
  systemd.services.flatpak-install-gnome-apps = lib.mkIf config.services.flatpak.enable {
    description = "Install GNOME Flatpak apps (once)";
    wantedBy    = [ "multi-user.target" ];
    after       = [ "flatpak-install-apps.service" ];
    requires    = [ "flatpak-add-flathub.service" ];
    path        = [ pkgs.flatpak ];
    script = ''
      STAMP="/var/lib/flatpak/.gnome-apps-installed-${gnomeAppsHash}"
      if [ -f "$STAMP" ]; then exit 0; fi

      # Require at least 1.5 GB free before attempting installs.
      AVAIL_MB=$(df /var/lib/flatpak --output=avail -BM 2>/dev/null | tail -1 | tr -d 'M ' || echo 0)
      if [ "$AVAIL_MB" -lt 1536 ]; then
        echo "flatpak: only ''${AVAIL_MB} MB free — need 1536 MB; skipping this boot"
        exit 0
      fi

      # Migration: uninstall desktop-only apps from the htpc role.
      for app in org.gnome.Calculator org.gnome.Calendar org.gnome.Papers org.gnome.Snapshot; do
        if flatpak list --app --columns=application 2>/dev/null | grep -qx "$app"; then
          echo "flatpak: removing desktop-only app $app (role: htpc)"
          flatpak uninstall --noninteractive --assumeyes "$app" || true
        fi
      done

      # Migration: uninstall Totem on HTPC — mpv is the designated player.
      if flatpak list --app --columns=application 2>/dev/null | grep -qx "org.gnome.Totem"; then
        echo "flatpak: removing org.gnome.Totem (htpc role uses mpv)"
        flatpak uninstall --noninteractive --assumeyes org.gnome.Totem || true
      fi

      flatpak install --noninteractive --assumeyes flathub \
        ${lib.concatStringsSep " \\\n        " gnomeAppsToInstall}

      rm -f /var/lib/flatpak/.gnome-apps-installed \
            /var/lib/flatpak/.gnome-apps-installed-*
      touch "$STAMP"
    '';
    unitConfig = {
      StartLimitIntervalSec = 600;
      StartLimitBurst       = 10;
    };
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
      Restart         = "on-failure";
      RestartSec      = 60;
    };
  };
}
