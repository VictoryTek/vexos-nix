# modules/server/humidor.nix
# Humidor — self-hosted cigar/humidor collection tracker (Rust app). No
# nixpkgs package or NixOS module exists, so it is deployed as a
# two-container OCI stack: humidor (the app) + humidor-db (dedicated
# postgres:17), talking to each other over an isolated Docker network.
# Mirrors modules/server/joplin.nix, this repo's template for a two-container
# app+postgres OCI service. See:
#   .github/docs/subagent_docs/HUMIDOR_HOME_REGISTRY_spec.md
#
# No required configuration — vexos.server.humidor.enable = true; is enough:
#   - The Postgres password is generated automatically on first activation
#     and stored at dataDir/secrets/humidor-env (0600, root-only). The app
#     container gets a composed DATABASE_URL from a generated second env
#     file (dataDir/secrets/humidor-app-env) — see the stopgap note on
#     humidor-app-env-init below. The db container still reads discrete
#     POSTGRES_* vars from the original env file. Set
#     vexos.server.humidor.environmentFile yourself only if you want to
#     manage the secret through another backend (e.g. sops-nix).
#
# Backup: the live Postgres data directory is not file-backup-safe, so a
# nightly `pg_dump` writes a plain SQL dump to dataDir/dump, which is what
# this module registers in vexos.server.backup.servicePaths.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.humidor;
  dumpTimer = import ../lib/dump-timer.nix { inherit lib pkgs; };
  # If the operator doesn't supply their own secret backend, generate one
  # locally on first activation (see the humidor-secrets-init unit below).
  effectiveEnvFile =
    if cfg.environmentFile != null
    then cfg.environmentFile
    else "${cfg.dataDir}/secrets/humidor-env";
  # Generated env file holding the composed DATABASE_URL for the app
  # container (see the humidor-app-env-init unit below).
  appEnvFile = "${cfg.dataDir}/secrets/humidor-app-env";
in
{
  options.vexos.server.humidor = {
    enable = lib.mkEnableOption "Humidor cigar/humidor collection tracker";

    port = lib.mkOption {
      type = lib.types.port;
      default = 9898;
      description = "Host port for the Humidor app container.";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/humidor";
      description = ''
        Host directory for the Postgres data directory (dataDir/postgres)
        and the nightly SQL dump (dataDir/dump) that backup.nix picks up.
      '';
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Optional systemd EnvironmentFile containing POSTGRES_PASSWORD=<secret>,
        shared by both the humidor and humidor-db containers. Leave unset
        (the default) to have a random password generated automatically on
        first activation at dataDir/secrets/humidor-env — no manual secret
        setup required. Set this explicitly only to manage the password
        through another backend (e.g. sops-nix).
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open the firewall for Humidor's port.";
    };
  };

  config = lib.mkMerge [
  (lib.mkIf cfg.enable {
    # Not postgres/ — live pgdata is not file-backup-safe; the nightly
    # dump below is what actually captures the database.
    vexos.server.backup.servicePaths.humidor = [ "${cfg.dataDir}/dump" ];

    virtualisation.docker.enable = lib.mkDefault true;
    virtualisation.oci-containers.backend = lib.mkDefault "docker";

    # Dedicated Docker network so humidor can resolve humidor-db by
    # container name (Docker's embedded DNS only works on user-defined
    # networks, not the default bridge). Idempotent — safe to re-run.
    systemd.services."humidor-network" = {
      description   = "Create dedicated Docker network for the Humidor stack";
      wantedBy      = [ "multi-user.target" ];
      after         = [ "docker.service" ];
      requires      = [ "docker.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        ${pkgs.docker}/bin/docker network inspect humidor-net >/dev/null 2>&1 || \
          ${pkgs.docker}/bin/docker network create humidor-net
      '';
    };

    # Auto-generates the Postgres password on first activation when the
    # operator hasn't supplied their own environmentFile — this is what
    # makes vexos.server.humidor.enable = true; sufficient on its own, with
    # no manual secret creation required.
    systemd.services."humidor-secrets-init" = lib.mkIf (cfg.environmentFile == null) {
      description   = "Generate Humidor Postgres password on first activation";
      wantedBy      = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        install -d -m 0700 "${cfg.dataDir}/secrets"
        if [ ! -f "${effectiveEnvFile}" ]; then
          dbPass=$(${pkgs.openssl}/bin/openssl rand -hex 24)
          echo "POSTGRES_PASSWORD=$dbPass" > "${effectiveEnvFile}"
          chmod 0600 "${effectiveEnvFile}"
        fi
      '';
    };

    # STOPGAP for the DATABASE_URL-only image generation. The currently
    # published ghcr.io/victorytek/humidor image reads only a single composed
    # DATABASE_URL (postgresql:// scheme, handed to tokio-postgres, which
    # percent-decodes) and ignores discrete POSTGRES_* vars. The password only
    # exists at runtime in effectiveEnvFile, so this unit composes the URL
    # into a second env file for the app container. Once an image containing
    # upstream commit 27cfd31 (discrete POSTGRES_* support) is built and
    # published, this unit and appEnvFile can be dropped and the app
    # container can take POSTGRES_HOST/PORT/USER/DB in `environment` plus
    # effectiveEnvFile again. Runs on every start so a rotated password is
    # picked up.
    systemd.services."humidor-app-env-init" = {
      description   = "Compose DATABASE_URL for the Humidor app container";
      wantedBy      = [ "multi-user.target" ];
      after         = lib.optional (cfg.environmentFile == null) "humidor-secrets-init.service";
      requires      = lib.optional (cfg.environmentFile == null) "humidor-secrets-init.service";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        install -d -m 0700 "${cfg.dataDir}/secrets"
        pw=$(sed -n 's/^POSTGRES_PASSWORD=//p' "${effectiveEnvFile}" | head -n1)
        if [ -z "$pw" ]; then
          echo "POSTGRES_PASSWORD not found in ${effectiveEnvFile}" >&2
          exit 1
        fi
        encPw=$(${pkgs.jq}/bin/jq -rn --arg p "$pw" '$p|@uri')
        umask 077
        printf 'DATABASE_URL=postgresql://humidor_user:%s@humidor-db:5432/humidor_db\n' "$encPw" > "${appEnvFile}"
      '';
    };

    # No tmpfiles rule for dataDir/postgres: the postgres:17 image's root
    # entrypoint chowns PGDATA to its own UID on first run and expects to
    # own it thereafter. A "d ... root root" rule here would re-assert
    # root:root ownership on every activation (systemd-tmpfiles --create
    # runs on every nixos-rebuild switch), stripping access from the
    # already-running container without restarting it.
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0700 root root -"
      "d ${cfg.dataDir}/dump 0700 root root -"
    ];

    virtualisation.oci-containers.containers.humidor-db = {
      image = "postgres:17";
      environment = {
        POSTGRES_USER = "humidor_user";
        POSTGRES_DB   = "humidor_db";
      };
      environmentFiles = [ effectiveEnvFile ];
      volumes = [
        "${cfg.dataDir}/postgres:/var/lib/postgresql/data"
      ];
      extraOptions = [ "--network=humidor-net" ];
    };

    virtualisation.oci-containers.containers.humidor = {
      image = "ghcr.io/victorytek/humidor:latest";
      ports = [ "${toString cfg.port}:9898" ];
      environment = {
        PORT     = "9898";
        RUST_LOG = "info";
      };
      environmentFiles = [ appEnvFile ];
      extraOptions = [ "--network=humidor-net" ];
      dependsOn = [ "humidor-db" ];
    };

    systemd.services."docker-humidor-db".after    = [ "humidor-network.service" ] ++ lib.optional (cfg.environmentFile == null) "humidor-secrets-init.service";
    systemd.services."docker-humidor-db".requires = [ "humidor-network.service" ] ++ lib.optional (cfg.environmentFile == null) "humidor-secrets-init.service";
    systemd.services."docker-humidor".after       = [ "humidor-network.service" "humidor-app-env-init.service" ];
    systemd.services."docker-humidor".requires    = [ "humidor-network.service" "humidor-app-env-init.service" ];

    networking.firewall.allowedTCPPorts = lib.optional cfg.openFirewall cfg.port;
  })

  # Nightly SQL dump — the live postgres/ data directory is not safe to
  # file-backup directly, so the servicePaths entry above only backs up dump/.
  (lib.mkIf cfg.enable (dumpTimer.mkDumpTimer {
    name        = "humidor";
    container   = "humidor-db";
    command     = "pg_dump -U humidor_user humidor_db";
    outputPath  = "${cfg.dataDir}/dump/humidor.sql";
    description = "Dump Humidor PostgreSQL database for backup";
  }))
  ];
}
