# modules/server/photoprism.nix
# PhotoPrism — AI-powered photo management and organizer (OCI container).
# Deployed as a pinned container (photoprism/photoprism) rather than the
# nixpkgs package because the stable package is a year-old snapshot.
# Default port: 2342
#
# Upstream: https://github.com/photoprism/photoprism
#
# Storage: dataDir (default /var/lib/photoprism — the same directory the
# previous native service used as storagePath) holds the SQLite index,
# sidecar files and cache, so an existing install is picked up in place.
# originalsDir holds the photo library itself; point it at existing media
# storage. Files are written as userId:groupId (PHOTOPRISM_UID/GID).
#
# Admin password default path: /etc/nixos/secrets/photoprism-password
#   Override via vexos.server.photoprism.passwordFile for alternate backends.
# Create file (plaintext, single line):
#   Create with: sudo install -m 0600 -o root -g root /dev/stdin /etc/nixos/secrets/photoprism-password
#   Permissions enforced at boot by modules/secrets.nix (0700 dir, 0600 files).
# The file is read as root at container start and handed to the container as
# PHOTOPRISM_ADMIN_PASSWORD through a root-only env file under /run, because
# the app drops privileges and could not read a 0600 root-owned bind mount.
# PhotoPrism only applies it when creating the admin user on first start.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.photoprism;
  storageMounts = import ../lib/storage-mount-ordering.nix { inherit lib; };
  envFile = "/run/photoprism-container/env";
in
{
  options.vexos.server.photoprism = {
    enable = lib.mkEnableOption "PhotoPrism photo management";

    mediaMounts = storageMounts.mediaMountsOption;

    port = lib.mkOption {
      type = lib.types.port;
      default = 2342;
      description = "Host port for the PhotoPrism web interface.";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/photoprism";
      description = ''
        Host directory bind-mounted to /photoprism/storage — database,
        sidecar files and cache. The default matches the old native
        service's storagePath so existing data is reused.
      '';
    };

    originalsDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/photoprism/originals";
      description = ''
        Host path bind-mounted to /photoprism/originals — the photo and
        video library. Override to point at existing storage (e.g. a
        mergerfs or storage-remote pool) and list its mountpoint in
        mediaMounts. Not included in backup paths: media libraries are
        usually covered by their own storage tier.
      '';
    };

    userId = lib.mkOption {
      type = lib.types.int;
      default = 1000;
      description = "Passed as PHOTOPRISM_UID; owner of files PhotoPrism writes.";
    };

    groupId = lib.mkOption {
      type = lib.types.int;
      default = 1000;
      description = "Passed as PHOTOPRISM_GID.";
    };

    passwordFile = lib.mkOption {
      type = lib.types.str;
      default = "/etc/nixos/secrets/photoprism-password";
      description = ''
        Path to the PhotoPrism admin password file.
        Default keeps legacy plaintext behavior; the sops backend overrides this
        to a decrypted runtime secret path.
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open the firewall for PhotoPrism's port.";
    };
  };

  config = lib.mkIf cfg.enable {
    # dataDir only — originalsDir is media, see the option description above.
    vexos.server.backup.servicePaths.photoprism = [ cfg.dataDir ];

    virtualisation.docker.enable = lib.mkDefault true;
    virtualisation.oci-containers.backend = lib.mkDefault "docker";

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 ${toString cfg.userId} ${toString cfg.groupId} -"
      "d ${cfg.originalsDir} 0755 ${toString cfg.userId} ${toString cfg.groupId} -"
    ];

    virtualisation.oci-containers.containers.photoprism = {
      image = "photoprism/photoprism:261007";
      ports = [ "${toString cfg.port}:2342" ];
      environment = {
        PHOTOPRISM_UID = toString cfg.userId;
        PHOTOPRISM_GID = toString cfg.groupId;
        PHOTOPRISM_ADMIN_USER = "admin";
        TZ = config.time.timeZone;
      };
      environmentFiles = [ envFile ];
      volumes = [
        "${cfg.dataDir}:/photoprism/storage"
        "${cfg.originalsDir}:/photoprism/originals"
      ];
    };

    # Render the admin password into a root-only env file just before the
    # container starts (preStart runs ahead of the generated `docker run`).
    systemd.services.docker-photoprism = {
      preStart = lib.mkBefore ''
        install -d -m 0700 /run/photoprism-container
        umask 0077
        printf 'PHOTOPRISM_ADMIN_PASSWORD=%s\n' "$(cat ${lib.escapeShellArg cfg.passwordFile})" > ${envFile}
      '';
      # Order after photo library storage — local (mergerfs/ZFS) or remote
      # (storage-remote.nix, automount-based). See mediaMounts above.
      unitConfig = storageMounts.requiresMountsFor cfg.mediaMounts;
    };

    networking.firewall.allowedTCPPorts = lib.optional cfg.openFirewall cfg.port;
  };
}
