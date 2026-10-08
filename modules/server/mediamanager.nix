# modules/server/mediamanager.nix
# MediaManager — self-hosted TV/movie request-and-download manager
# (maxdorninger/MediaManager). No nixpkgs package or module exists, so it is
# deployed as a two-container OCI stack: mediamanager (the app) +
# mediamanager-db (dedicated postgres:17), talking over an isolated Docker
# network. Mirrors modules/server/joplin.nix.
#
# Upstream: https://github.com/maxdorninger/MediaManager
#
# Configuration is supplied entirely through MEDIAMANAGER_* environment
# variables (upstream's pydantic settings, "__" as the nested delimiter), so no
# config.toml is generated. If you need settings this module doesn't expose
# (indexers, torrent clients, metadata providers, libraries, notifications),
# drop a config.toml into dataDir/config — environment variables take
# precedence over it.
#
# Required: vexos.server.mediamanager.adminEmails — users registering with one
# of these addresses become administrators. Registration is otherwise closed,
# so without it nobody can log in.
#
# Secrets (Postgres password, token signing secret) are generated on first
# activation at dataDir/secrets/mediamanager-env (0600, root-only). Set
# environmentFile only to manage them through another backend (e.g. sops-nix).
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.mediamanager;
  dumpTimer = import ../lib/dump-timer.nix { inherit lib pkgs; };
  storageMounts = import ../lib/storage-mount-ordering.nix { inherit lib; };
  effectiveEnvFile =
    if cfg.environmentFile != null
    then cfg.environmentFile
    else "${cfg.dataDir}/secrets/mediamanager-env";
  secretsUnit = lib.optional (cfg.environmentFile == null) "mediamanager-secrets-init.service";
in
{
  options.vexos.server.mediamanager = {
    enable = lib.mkEnableOption "MediaManager TV/movie manager";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8000;
      description = "Host port for the MediaManager web UI (upstream's own default).";
    };

    adminEmails = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "me@example.com" ];
      description = ''
        Email addresses that become administrators when they register. The
        first address is also used to create the initial admin account when no
        users exist. Required.
      '';
    };

    frontendUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://${config.networking.hostName}:${toString cfg.port}";
      description = ''
        URL users reach the web UI at (no trailing slash). Also used as the
        CORS origin. Set it to the public URL if you put a reverse proxy in
        front of MediaManager.
      '';
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/mediamanager";
      description = ''
        Host directory for the app config (dataDir/config), the Postgres data
        directory (dataDir/postgres), the nightly SQL dump (dataDir/dump) and
        the generated secrets (dataDir/secrets).
      '';
    };

    libraryDir = lib.mkOption {
      type = lib.types.str;
      default = "${cfg.dataDir}/data";
      description = ''
        Host path bind-mounted to /data. MediaManager uses /data/tv,
        /data/movies, /data/torrents (where download clients drop completed
        files) and /data/images beneath it. Override to point at existing
        storage (e.g. a mergerfs or storage-remote pool).

        Not included in backup paths — media libraries are typically far too
        large for the restic repo.
      '';
    };

    mediaMounts = storageMounts.mediaMountsOption;

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Optional systemd EnvironmentFile supplying POSTGRES_PASSWORD,
        MEDIAMANAGER_DATABASE__PASSWORD (same value) and
        MEDIAMANAGER_AUTH__TOKEN_SECRET. Leave unset to have them generated
        automatically on first activation.
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open the firewall for MediaManager's port.";
    };
  };

  config = lib.mkMerge [
  (lib.mkIf cfg.enable {
    assertions = [{
      assertion = cfg.adminEmails != [ ];
      message = "vexos.server.mediamanager.adminEmails must contain at least one address, otherwise nobody can log in.";
    }];

    # Not postgres/ — live pgdata is not file-backup-safe; the nightly dump
    # below captures the database. config/ holds any hand-written config.toml.
    vexos.server.backup.servicePaths.mediamanager = [ "${cfg.dataDir}/dump" "${cfg.dataDir}/config" ];

    virtualisation.docker.enable = lib.mkDefault true;
    virtualisation.oci-containers.backend = lib.mkDefault "docker";

    # Dedicated Docker network so the app can resolve mediamanager-db by
    # container name. Idempotent — safe to re-run.
    systemd.services."mediamanager-network" = {
      description   = "Create dedicated Docker network for the MediaManager stack";
      wantedBy      = [ "multi-user.target" ];
      after         = [ "docker.service" ];
      requires      = [ "docker.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        ${pkgs.docker}/bin/docker network inspect mediamanager-net >/dev/null 2>&1 || \
          ${pkgs.docker}/bin/docker network create mediamanager-net
      '';
    };

    systemd.services."mediamanager-secrets-init" = lib.mkIf (cfg.environmentFile == null) {
      description   = "Generate MediaManager secrets on first activation";
      wantedBy      = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        install -d -m 0700 "${cfg.dataDir}/secrets"
        if [ ! -f "${effectiveEnvFile}" ]; then
          dbPass=$(${pkgs.openssl}/bin/openssl rand -hex 24)
          {
            echo "POSTGRES_PASSWORD=$dbPass"
            echo "MEDIAMANAGER_DATABASE__PASSWORD=$dbPass"
            echo "MEDIAMANAGER_AUTH__TOKEN_SECRET=$(${pkgs.openssl}/bin/openssl rand -hex 32)"
          } > "${effectiveEnvFile}"
          chmod 0600 "${effectiveEnvFile}"
        fi
      '';
    };

    # No tmpfiles rule for dataDir/postgres: the postgres image chowns PGDATA
    # to its own UID on first run; re-asserting root ownership on every
    # activation would lock the running container out (see joplin.nix).
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 root root -"
      "d ${cfg.dataDir}/config 0755 root root -"
      "d ${cfg.dataDir}/dump 0700 root root -"
      "d ${cfg.libraryDir} 0755 root root -"
    ];

    virtualisation.oci-containers.containers.mediamanager-db = {
      image = "postgres:17.11";
      environment = {
        POSTGRES_USER = "MediaManager";
        POSTGRES_DB   = "MediaManager";
      };
      environmentFiles = [ effectiveEnvFile ];
      volumes = [ "${cfg.dataDir}/postgres:/var/lib/postgresql/data" ];
      extraOptions = [ "--network=mediamanager-net" ];
    };

    virtualisation.oci-containers.containers.mediamanager = {
      image = "quay.io/maxdorninger/mediamanager:1.12.3";
      ports = [ "${toString cfg.port}:8000" ];
      # Upstream documents no PUID/PGID support, so the container runs as the
      # image's default user and the bind mounts are left root-owned.
      environment = {
        CONFIG_DIR = "/app/config";
        TZ         = config.time.timeZone;
        MEDIAMANAGER_DATABASE__HOST   = "mediamanager-db";
        MEDIAMANAGER_DATABASE__PORT   = "5432";
        MEDIAMANAGER_DATABASE__USER   = "MediaManager";
        MEDIAMANAGER_DATABASE__DBNAME = "MediaManager";
        MEDIAMANAGER_MISC__FRONTEND_URL    = cfg.frontendUrl;
        MEDIAMANAGER_MISC__CORS_URLS       = builtins.toJSON [ cfg.frontendUrl ];
        MEDIAMANAGER_MISC__IMAGE_DIRECTORY   = "/data/images";
        MEDIAMANAGER_MISC__TV_DIRECTORY      = "/data/tv";
        MEDIAMANAGER_MISC__MOVIE_DIRECTORY   = "/data/movies";
        MEDIAMANAGER_MISC__TORRENT_DIRECTORY = "/data/torrents";
        MEDIAMANAGER_AUTH__ADMIN_EMAILS = builtins.toJSON cfg.adminEmails;
      };
      environmentFiles = [ effectiveEnvFile ];
      volumes = [
        "${cfg.dataDir}/config:/app/config"
        "${cfg.libraryDir}:/data"
      ];
      extraOptions = [ "--network=mediamanager-net" ];
      dependsOn = [ "mediamanager-db" ];
    };

    systemd.services."docker-mediamanager-db" = {
      after    = [ "mediamanager-network.service" ] ++ secretsUnit;
      requires = [ "mediamanager-network.service" ] ++ secretsUnit;
    };
    systemd.services."docker-mediamanager" = {
      after    = [ "mediamanager-network.service" ] ++ secretsUnit;
      requires = [ "mediamanager-network.service" ] ++ secretsUnit;
      unitConfig = storageMounts.requiresMountsFor cfg.mediaMounts;
    };

    networking.firewall.allowedTCPPorts = lib.optional cfg.openFirewall cfg.port;
  })

  # Nightly SQL dump — the live postgres/ data directory is not file-backup-safe.
  (lib.mkIf cfg.enable (dumpTimer.mkDumpTimer {
    name        = "mediamanager";
    container   = "mediamanager-db";
    command     = "pg_dump -U MediaManager MediaManager";
    outputPath  = "${cfg.dataDir}/dump/mediamanager.sql";
    description = "Dump MediaManager PostgreSQL database for backup";
  }))
  ];
}
