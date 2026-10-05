# modules/server/listenarr.nix
# Listenarr — audiobook collection manager (Sonarr/Radarr-style, for
# audiobooks). No nixpkgs package or module exists, so it is deployed as a
# single OCI container with a self-contained database under /app/config — same
# shape as bookshelf.nix.
#
# Upstream: https://github.com/Listenarrs/Listenarr
#
# Image tag: upstream currently publishes only the rolling "canary" tag (all
# GitHub releases are pre-releases), so this module tracks it. Pin a specific
# vX.Y.Z-canary tag here once upstream publishes stable releases.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.listenarr;
  storageMounts = import ../lib/storage-mount-ordering.nix { inherit lib; };
in
{
  options.vexos.server.listenarr = {
    enable = lib.mkEnableOption "Listenarr audiobook collection manager";

    port = lib.mkOption {
      type = lib.types.port;
      default = 4545;
      description = "Host port for the Listenarr web UI (upstream's own default).";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/listenarr";
      description = "Host directory bind-mounted to /app/config — configuration and database.";
    };

    libraryDir = lib.mkOption {
      type = lib.types.str;
      default = "${cfg.dataDir}/audiobooks";
      description = ''
        Host path bind-mounted to /audiobooks — the audiobook library.
        Override to point at existing storage (e.g. the directory
        Audiobookshelf reads from).

        Not included in this service's backup paths: media libraries are
        typically far too large for the restic repo.
      '';
    };

    downloadsDir = lib.mkOption {
      type = lib.types.str;
      default = "${cfg.dataDir}/downloads";
      description = ''
        Host path bind-mounted to /downloads — where download clients drop
        completed files. Point it at your download client's completed-downloads
        directory so Listenarr can import from it.
      '';
    };

    mediaMounts = storageMounts.mediaMountsOption;

    userId = lib.mkOption {
      type = lib.types.int;
      default = 1000;
      description = "Passed as PUID, and used to pre-create the host directories with matching ownership.";
    };

    groupId = lib.mkOption {
      type = lib.types.int;
      default = 1000;
      description = "Passed as PGID.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open the firewall for Listenarr's port.";
    };
  };

  config = lib.mkIf cfg.enable {
    vexos.server.backup.servicePaths.listenarr = [ cfg.dataDir ];

    virtualisation.docker.enable = lib.mkDefault true;
    virtualisation.oci-containers.backend = lib.mkDefault "docker";

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 ${toString cfg.userId} ${toString cfg.groupId} -"
      "d ${cfg.libraryDir} 0755 ${toString cfg.userId} ${toString cfg.groupId} -"
      "d ${cfg.downloadsDir} 0755 ${toString cfg.userId} ${toString cfg.groupId} -"
    ];

    virtualisation.oci-containers.containers.listenarr = {
      image = "ghcr.io/listenarrs/listenarr:canary";
      ports = [ "${toString cfg.port}:4545" ];
      environment = {
        PUID  = toString cfg.userId;
        PGID  = toString cfg.groupId;
        UMASK = "022";
        TZ    = config.time.timeZone;
      };
      volumes = [
        "${cfg.dataDir}:/app/config"
        "${cfg.libraryDir}:/audiobooks"
        "${cfg.downloadsDir}:/downloads"
      ];
    };

    # Order the container after its library storage (local or remote).
    systemd.services."docker-listenarr".unitConfig = storageMounts.requiresMountsFor cfg.mediaMounts;

    networking.firewall.allowedTCPPorts = lib.optional cfg.openFirewall cfg.port;
  };
}
