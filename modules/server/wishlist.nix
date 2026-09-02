# modules/server/wishlist.nix
# Wishlist — self-hosted wishlist / gift registry (cmintey/wishlist).
# No nixpkgs package or NixOS module exists, so it is deployed as a single
# OCI container. Unlike grimmory.nix/joplin.nix this is a one-container
# module: Wishlist stores everything in a SQLite database under
# dataDir/data, so there is no companion db container, no dedicated Docker
# network, and no generated credentials to manage.
#
# Upstream: https://github.com/cmintey/wishlist
#
# ORIGIN is the one setting Wishlist genuinely requires — it validates
# request origins against it, and a mismatch produces sign-in/upload
# failures rather than an obvious error. vexos.server.wishlist.origin
# defaults to "http://<networking.hostName>:<port>"; override it if you
# reach the service through a reverse proxy or a different name.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.wishlist;
in
{
  options.vexos.server.wishlist = {
    enable = lib.mkEnableOption "Wishlist gift registry";

    port = lib.mkOption {
      type = lib.types.port;
      default = 3280;
      description = "Host port for the Wishlist container (upstream's own default).";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/wishlist";
      description = ''
        Host directory holding the SQLite database (dataDir/data) and
        user-uploaded images (dataDir/uploads).
      '';
    };

    origin = lib.mkOption {
      type = lib.types.str;
      default = "http://${config.networking.hostName}:${toString cfg.port}";
      description = ''
        URL users actually connect to, passed as ORIGIN. Wishlist validates
        request origins against this value — if it doesn't match how the
        service is reached, sign-in and uploads fail. Include the port
        unless you're serving it on 80/443 behind a reverse proxy.
      '';
    };

    tokenTime = lib.mkOption {
      type = lib.types.int;
      default = 72;
      description = "Hours until signup and password-reset tokens expire (TOKEN_TIME).";
    };

    userId = lib.mkOption {
      type = lib.types.int;
      default = 1000;
      description = ''
        Owner UID for dataDir/data and dataDir/uploads. The upstream image
        does not document PUID/PGID support and does not self-chown its
        mounts, so these directories are pre-created with this ownership
        rather than the vars being passed to the container.
      '';
    };

    groupId = lib.mkOption {
      type = lib.types.int;
      default = 1000;
      description = "Owner GID for dataDir/data and dataDir/uploads.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open the firewall for Wishlist's port.";
    };
  };

  config = lib.mkIf cfg.enable {
    # The SQLite database lives under data/. Copying a live SQLite file is
    # not strictly transaction-safe, but the image ships no dump tool to
    # drive modules/lib/dump-timer.nix with, so the directory is backed up
    # directly — the same treatment every other single-container service in
    # this repo gets.
    vexos.server.backup.servicePaths.wishlist = [ cfg.dataDir ];

    virtualisation.docker.enable = lib.mkDefault true;
    virtualisation.oci-containers.backend = lib.mkDefault "docker";

    # Both mounts are plain bind mounts written by the app itself — neither
    # is a self-chowning database image mount, so unlike grimmory's
    # mariadb-config/ or joplin's postgres/ both get tmpfiles rules.
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 root root -"
      "d ${cfg.dataDir}/data 0755 ${toString cfg.userId} ${toString cfg.groupId} -"
      "d ${cfg.dataDir}/uploads 0755 ${toString cfg.userId} ${toString cfg.groupId} -"
    ];

    virtualisation.oci-containers.containers.wishlist = {
      image = "ghcr.io/cmintey/wishlist:v0.66.0";
      ports = [ "${toString cfg.port}:3280" ];
      environment = {
        ORIGIN     = cfg.origin;
        TOKEN_TIME = toString cfg.tokenTime;
        TZ         = config.time.timeZone;
      };
      volumes = [
        "${cfg.dataDir}/data:/usr/src/app/data"
        "${cfg.dataDir}/uploads:/usr/src/app/uploads"
      ];
    };

    networking.firewall.allowedTCPPorts = lib.optional cfg.openFirewall cfg.port;
  };
}
