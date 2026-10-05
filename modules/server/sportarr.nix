# modules/server/sportarr.nix
# Sportarr — Sonarr-style PVR for sports (events, leagues, fights). No nixpkgs
# package or module exists, so it is deployed as a single OCI container with a
# self-contained database under /config — same shape as bookshelf.nix.
#
# Upstream: https://github.com/Sportarr/Sportarr
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.sportarr;
  storageMounts = import ../lib/storage-mount-ordering.nix { inherit lib; };
in
{
  options.vexos.server.sportarr = {
    enable = lib.mkEnableOption "Sportarr sports PVR";

    port = lib.mkOption {
      type = lib.types.port;
      default = 1867;
      description = "Host port for the Sportarr web UI (upstream's own default).";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/sportarr";
      description = "Host directory bind-mounted to /config — configuration and database.";
    };

    libraryDir = lib.mkOption {
      type = lib.types.str;
      default = "${cfg.dataDir}/data";
      description = ''
        Host path bind-mounted to /data — the sports library and download
        staging area. Override to point at existing storage (e.g. a mergerfs
        or storage-remote pool).

        Not included in this service's backup paths: media libraries are
        typically far too large for the restic repo. Add it to
        vexos.server.backup.extraPaths if you want it captured.
      '';
    };

    mediaMounts = storageMounts.mediaMountsOption;

    userId = lib.mkOption {
      type = lib.types.int;
      default = 1000;
      description = "Passed as PUID, and used to pre-create dataDir/libraryDir with matching ownership.";
    };

    groupId = lib.mkOption {
      type = lib.types.int;
      default = 1000;
      description = "Passed as PGID.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open the firewall for Sportarr's port.";
    };
  };

  config = lib.mkIf cfg.enable {
    vexos.server.backup.servicePaths.sportarr = [ cfg.dataDir ];

    virtualisation.docker.enable = lib.mkDefault true;
    virtualisation.oci-containers.backend = lib.mkDefault "docker";

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 ${toString cfg.userId} ${toString cfg.groupId} -"
      "d ${cfg.libraryDir} 0755 ${toString cfg.userId} ${toString cfg.groupId} -"
    ];

    virtualisation.oci-containers.containers.sportarr = {
      image = "sportarr/sportarr:4.1.9.1119";
      ports = [ "${toString cfg.port}:1867" ];
      environment = {
        PUID  = toString cfg.userId;
        PGID  = toString cfg.groupId;
        UMASK = "022";
        TZ    = config.time.timeZone;
      };
      volumes = [
        "${cfg.dataDir}:/config"
        "${cfg.libraryDir}:/data"
      ];
    };

    # Order the container after its library storage (local or remote).
    systemd.services."docker-sportarr".unitConfig = storageMounts.requiresMountsFor cfg.mediaMounts;

    networking.firewall.allowedTCPPorts = lib.optional cfg.openFirewall cfg.port;
  };
}
