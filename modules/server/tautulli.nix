# modules/server/tautulli.nix
# Tautulli — monitoring and analytics for Plex Media Server (OCI container).
# Deployed as a pinned container (ghcr.io/tautulli/tautulli) rather than the
# nixpkgs package because the stable package lags upstream: existing data
# written by 2.18.x cannot be read by the 2.17.x that stable ships.
# Default port: 8181
#
# Upstream: https://github.com/Tautulli/Tautulli
#
# dataDir defaults to /var/lib/plexpy — the directory the previous native
# service used — so an existing install's config.ini and database are picked
# up in place. The image's entrypoint (PUID/PGID) chowns /config itself, so
# no manual ownership fix is required.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.tautulli;
in
{
  options.vexos.server.tautulli = {
    enable = lib.mkEnableOption "Tautulli Plex analytics";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8181;
      description = "Host port for the Tautulli web interface.";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/plexpy";
      description = ''
        Host directory bind-mounted to /config — Tautulli's config.ini,
        database, and logs. The default matches the old native service's
        data directory so existing data is reused.
      '';
    };

    userId = lib.mkOption {
      type = lib.types.int;
      default = 1000;
      description = "Passed as PUID; the image chowns dataDir to this user.";
    };

    groupId = lib.mkOption {
      type = lib.types.int;
      default = 1000;
      description = "Passed as PGID.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open the firewall for Tautulli's port.";
    };
  };

  config = lib.mkIf cfg.enable {
    vexos.server.backup.servicePaths.tautulli = [ cfg.dataDir ];

    virtualisation.docker.enable = lib.mkDefault true;
    virtualisation.oci-containers.backend = lib.mkDefault "docker";

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 ${toString cfg.userId} ${toString cfg.groupId} -"
    ];

    virtualisation.oci-containers.containers.tautulli = {
      image = "ghcr.io/tautulli/tautulli:v2.18.2";
      ports = [ "${toString cfg.port}:8181" ];
      environment = {
        PUID = toString cfg.userId;
        PGID = toString cfg.groupId;
        TZ   = config.time.timeZone;
      };
      volumes = [ "${cfg.dataDir}:/config" ];
    };

    networking.firewall.allowedTCPPorts = lib.optional cfg.openFirewall cfg.port;
  };
}
