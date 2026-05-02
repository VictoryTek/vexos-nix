# modules/gnome-desktop.nix
# Desktop-only GNOME additions: GameMode shell extension, blue accent,
# desktop favourites, and the Flatpak install service for the desktop role
# (TextEditor, Loupe, Totem, Calculator, Calendar, Papers, Snapshot).
{ config, pkgs, lib, ... }:
let
  # Local app lists for the systemd flatpak-install service.
  gnomeBaseApps = [
    "org.gnome.TextEditor"
    "org.gnome.Loupe"
    "org.gnome.Totem"
  ];

  gnomeDesktopOnlyApps = [
    "org.gnome.Calculator"
    "org.gnome.Calendar"
    "org.gnome.Papers"
    "org.gnome.Snapshot"
  ];

  gnomeAppsToInstall = gnomeBaseApps ++ gnomeDesktopOnlyApps;

  gnomeAppsHash = builtins.substring 0 16
    (builtins.hashString "sha256" (lib.concatStringsSep "," gnomeAppsToInstall));

  # Common shell extensions enabled on every role.
  commonExtensions = [
    "appindicatorsupport@rgcjonas.gmail.com"
    # "dash-to-dock@micxgx.gmail.com"  # disabled: autohide broken
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
            commonExtensions ++ [ "gamemodeshellextension@trsnaqe.com" ];
          favorite-apps = [
            "brave-browser.desktop"
            "app.zen_browser.zen.desktop"
            "org.gnome.Nautilus.desktop"
            "com.mitchellh.ghostty.desktop"
            "io.github.up.desktop"
            "org.gnome.Boxes.desktop"
            "virtualbox.desktop"
            "code.desktop"
          ];
        };
      };
    }
  ];

  # ── GNOME default app Flatpaks (desktop role) ─────────────────────────────
  # Installs GNOME apps from Flathub on first boot (stamp is app-list-hash based).
  # After initial install, Up manages updates.  Skipped entirely when
  # vexos.flatpak.enable = false (e.g. VM guests).
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
      # Exit 0 (not 1) so the switch doesn't fail — stamp is not written,
      # so the service will retry on the next boot.
      AVAIL_MB=$(df /var/lib/flatpak --output=avail -BM 2>/dev/null | tail -1 | tr -d 'M ' || echo 0)
      if [ "$AVAIL_MB" -lt 1536 ]; then
        echo "flatpak: only ''${AVAIL_MB} MB free — need 1536 MB; skipping this boot"
        exit 0
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
