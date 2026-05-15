# modules/gnome-flatpak-install.nix
# Shared systemd service for GNOME-role Flatpak app installation.
#
# Declares options.vexos.gnome.flatpakInstall.{apps,extraRemoves}.
# Each gnome-<role>.nix sets those options; this module generates the
# shared service body so the ~50-line definition is not copy-pasted four times.
#
# Activation condition: services.flatpak.enable == true AND apps != [].
# When apps = [] (the default) no service is defined.
{ config, pkgs, lib, ... }:
let
  cfg = config.vexos.gnome.flatpakInstall;

  # Hash of desired apps + migration removes, baked in at Nix evaluation time.
  # Including extraRemoves ensures the stamp changes whenever the remove list
  # changes, forcing a re-run that cleans up the unwanted apps.
  appsHash = builtins.substring 0 16
    (builtins.hashString "sha256"
      (lib.concatStringsSep "," (cfg.apps ++ cfg.extraRemoves)));
in
{
  options.vexos.gnome.flatpakInstall = {
    apps = lib.mkOption {
      type        = lib.types.listOf lib.types.str;
      default     = [];
      description = "GNOME Flatpak app IDs to install from Flathub for this role.";
    };

    extraRemoves = lib.mkOption {
      type        = lib.types.listOf lib.types.str;
      default     = [];
      description = ''
        App IDs to uninstall for migration (apps that were previously installed
        but are no longer desired for this role).  Included in the stamp hash so
        removal is triggered exactly once when the list changes.
      '';
    };
  };

  config = lib.mkIf (config.services.flatpak.enable && cfg.apps != []) {
    systemd.services.flatpak-install-gnome-apps = {
      description = "Install GNOME Flatpak apps (once)";
      wantedBy    = [ "multi-user.target" ];
      after       = [ "flatpak-install-apps.service" ];
      requires    = [ "flatpak-add-flathub.service" ];
      path        = [ pkgs.flatpak ];
      script = ''
        STAMP="/var/lib/flatpak/.gnome-apps-installed-${appsHash}"
        if [ -f "$STAMP" ]; then exit 0; fi

        # Require at least 1.5 GB free before attempting installs.
        # Exit 0 (not 1) so the switch doesn't fail — stamp is not written,
        # so the service will retry on the next boot.
        AVAIL_MB=$(df /var/lib/flatpak --output=avail -BM 2>/dev/null | tail -1 | tr -d 'M ' || echo 0)
        if [ "$AVAIL_MB" -lt 1536 ]; then
          echo "flatpak: only ''${AVAIL_MB} MB free — need 1536 MB; skipping this boot"
          exit 0
        fi

        ${lib.concatMapStrings (app: ''
          if flatpak list --app --columns=application 2>/dev/null | grep -qx "${app}"; then
            echo "flatpak: removing ${app} (migration)"
            flatpak uninstall --noninteractive --assumeyes ${app} || true
          fi
        '') cfg.extraRemoves}
        flatpak install --noninteractive --assumeyes flathub \
          ${lib.concatStringsSep " \\\n          " cfg.apps}

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
  };
}
