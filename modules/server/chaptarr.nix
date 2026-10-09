# modules/server/chaptarr.nix
# Chaptarr — audiobook and ebook collection manager for Usenet and BitTorrent,
# a re-work of the retired Readarr that handles both media types in one
# instance. No nixpkgs package or module exists, so it is deployed as a single
# OCI container with a self-contained SQLite database under /config — same
# shape as sportarr.nix.
#
# Upstream is beta software; Docker is its only supported install method.
# Image: https://hub.docker.com/r/chaptarr/chaptarr
#
# In Prowlarr, add it as a Readarr-type application (the API is compatible).
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.chaptarr;
  storageMounts = import ../lib/storage-mount-ordering.nix { inherit lib; };
in
{
  options.vexos.server.chaptarr = {
    enable = lib.mkEnableOption "Chaptarr audiobook and ebook collection manager";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8789;
      description = "Host port for the Chaptarr web UI (upstream's own default).";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/chaptarr";
      description = "Host directory bind-mounted to /config — configuration and SQLite database.";
    };

    libraryDir = lib.mkOption {
      type = lib.types.str;
      default = "${cfg.dataDir}/data";
      description = ''
        Host path bind-mounted to /data — the audiobook/ebook libraries and
        download staging area. Keep libraries and downloads under this one
        parent (set the root folders to e.g. /data/audiobooks and
        /data/ebooks in the UI) so imports can hardlink instead of copying.
        Override to point at existing storage (e.g. a mergerfs or
        storage-remote pool).

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
      description = "Open the firewall for Chaptarr's port.";
    };
  };

  config = lib.mkIf cfg.enable {
    # dataDir only — libraryDir is media, see the option description above.
    vexos.server.backup.servicePaths.chaptarr = [ cfg.dataDir ];

    virtualisation.docker.enable = lib.mkDefault true;
    virtualisation.oci-containers.backend = lib.mkDefault "docker";

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 ${toString cfg.userId} ${toString cfg.groupId} -"
      "d ${cfg.libraryDir} 0755 ${toString cfg.userId} ${toString cfg.groupId} -"
    ];

    virtualisation.oci-containers.containers.chaptarr = {
      image = "chaptarr/chaptarr:0.9.965";
      ports = [ "${toString cfg.port}:8789" ];
      environment = {
        PUID  = toString cfg.userId;
        PGID  = toString cfg.groupId;
        UMASK = "002";
        TZ    = config.time.timeZone;
      };
      volumes = [
        "${cfg.dataDir}:/config"
        "${cfg.libraryDir}:/data"
      ];
    };

    # Order the container after its library storage (local or remote).
    systemd.services."docker-chaptarr".unitConfig = storageMounts.requiresMountsFor cfg.mediaMounts;

    networking.firewall.allowedTCPPorts = lib.optional cfg.openFirewall cfg.port;
  };
}
