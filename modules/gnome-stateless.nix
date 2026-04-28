# modules/gnome-stateless.nix
# Stateless-only GNOME additions: teal accent, stateless dock favourites, and
# the Flatpak install service for the stateless role (TextEditor, Loupe, Totem).
{ config, pkgs, lib, ... }:
let
  # Local app list for the systemd flatpak-install service.
  gnomeAppsToInstall = [
    "org.gnome.TextEditor"
    "org.gnome.Loupe"
    "org.gnome.Totem"
  ];

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

  # ── Stateless bloat reduction (in addition to the universal list) ─────────
  environment.gnome.excludePackages = with pkgs; [
    papers            # Flatpak org.gnome.Papers installed on desktop only
  ];

  # ── Role-specific dconf overlay ───────────────────────────────────────────
  programs.dconf.profiles.user.databases = [
    {
      settings = {
        "org/gnome/desktop/interface" = {
          accent-color = "teal";
        };

        "org/gnome/shell" = {
          enabled-extensions = commonExtensions;
          favorite-apps = [
            "brave-browser.desktop"
            "torbrowser.desktop"
            "app.zen_browser.zen.desktop"
            "org.gnome.Nautilus.desktop"
            "com.mitchellh.ghostty.desktop"
            "io.github.up.desktop"
          ];
        };
      };
    }
  ];

  # ── GNOME default app Flatpaks (stateless role) ───────────────────────────
  # Includes migration cleanup for desktop-only apps that may have been
  # installed under previous configurations.
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

      # Migration: uninstall desktop-only apps from the stateless role.
      for app in org.gnome.Calculator org.gnome.Calendar org.gnome.Papers org.gnome.Snapshot; do
        if flatpak list --app --columns=application 2>/dev/null | grep -qx "$app"; then
          echo "flatpak: removing desktop-only app $app (role: stateless)"
          flatpak uninstall --noninteractive --assumeyes "$app" || true
        fi
      done

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
