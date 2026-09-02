# modules/server/bookshelf.nix
# Bookshelf — ebook/audiobook collection manager for Usenet and BitTorrent
# (pennydreadful/bookshelf), a revival of the discontinued Readarr. Single
# OCI container: it keeps its own self-contained database under /config, so
# like wishlist.nix — and unlike grimmory.nix/joplin.nix — there is no
# companion db container, no dedicated Docker network, and no generated
# credentials.
#
# Upstream: https://github.com/pennydreadful/bookshelf
#
# Image tag: this module tracks the "hardcover" line, which uses Hardcover
# as the metadata provider. Upstream is explicit that hardcover images are
# NOT compatible with an existing Readarr database and need a fresh
# deployment — do not point dataDir at an old Readarr config directory.
# (The alternative "softcover" line keeps Goodreads metadata and Readarr
# database compatibility, at noticeably worse metadata quality.)
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.bookshelf;
in
{
  options.vexos.server.bookshelf = {
    enable = lib.mkEnableOption "Bookshelf ebook/audiobook collection manager";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8787;
      description = "Host port for the Bookshelf web UI (upstream's own default).";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/bookshelf";
      description = ''
        Host directory bind-mounted to /config — Bookshelf's configuration
        and its self-contained database.

        Must NOT be pointed at an existing Readarr config directory: the
        hardcover image this module runs cannot read a Readarr database.
      '';
    };

    libraryDir = lib.mkOption {
      type = lib.types.str;
      default = "${cfg.dataDir}/library";
      description = ''
        Host path bind-mounted to /data — the ebook/audiobook library and
        download staging area. Override to point at existing storage (e.g. a
        mergerfs or storage-remote pool) instead of the dataDir-relative
        default.

        Not included in this service's backup paths: media libraries are
        typically far too large for the restic repo and are usually covered
        by their own storage tier. Add it to
        vexos.server.backup.extraPaths if you do want it captured.
      '';
    };

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
      description = "Open the firewall for Bookshelf's port.";
    };
  };

  config = lib.mkIf cfg.enable {
    # dataDir only — libraryDir is media, see the option description above.
    vexos.server.backup.servicePaths.bookshelf = [ cfg.dataDir ];

    virtualisation.docker.enable = lib.mkDefault true;
    virtualisation.oci-containers.backend = lib.mkDefault "docker";

    # Both are plain bind mounts the app writes into directly; neither is a
    # self-chowning database image mount, so both get tmpfiles rules.
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 ${toString cfg.userId} ${toString cfg.groupId} -"
      "d ${cfg.libraryDir} 0755 ${toString cfg.userId} ${toString cfg.groupId} -"
    ];

    virtualisation.oci-containers.containers.bookshelf = {
      image = "ghcr.io/pennydreadful/bookshelf:hardcover";
      ports = [ "${toString cfg.port}:8787" ];
      environment = {
        PUID = toString cfg.userId;
        PGID = toString cfg.groupId;
        TZ   = config.time.timeZone;
      };
      volumes = [
        "${cfg.dataDir}:/config"
        "${cfg.libraryDir}:/data"
      ];
    };

    networking.firewall.allowedTCPPorts = lib.optional cfg.openFirewall cfg.port;
  };
}
