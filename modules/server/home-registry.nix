# modules/server/home-registry.nix
# Home Registry — self-hosted home inventory tracker (Rust app). No nixpkgs
# package or NixOS module exists, so it is deployed as a two-container OCI
# stack: home-registry (the app) + home-registry-db (dedicated postgres:17),
# talking to each other over an isolated Docker network. Mirrors
# modules/server/joplin.nix, this repo's template for a two-container
# app+postgres OCI service. See:
#   .github/docs/subagent_docs/HUMIDOR_HOME_REGISTRY_spec.md
#
# No required configuration — vexos.server.home-registry.enable = true; is
# enough:
#   - The Postgres password is generated automatically on first activation
#     and stored at dataDir/secrets/home-registry-env (0600, root-only). The
#     app container gets a composed DATABASE_URL from a generated second env
#     file (dataDir/secrets/home-registry-app-env) — see the stopgap note on
#     home-registry-app-env-init below. The db container still reads
#     discrete POSTGRES_* vars from the original env file. Set
#     vexos.server.home-registry.environmentFile yourself only if you want to
#     manage the secret through another backend (e.g. sops-nix).
#   - The Postgres user (postgres) and database name (home_inventory) match
#     the upstream image's defaults, which are configurable via env vars as
#     of upstream commit 4c9dfc4 — see
#     .github/docs/subagent_docs/HUMIDOR_HOME_REGISTRY_upstream_notes.md.
#
# Backup: the live Postgres data directory is not file-backup-safe, so a
# nightly `pg_dump` writes a plain SQL dump to dataDir/dump, which is what
# this module registers in vexos.server.backup.servicePaths.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.home-registry;
  dumpTimer = import ../lib/dump-timer.nix { inherit lib pkgs; };
  # If the operator doesn't supply their own secret backend, generate one
  # locally on first activation (see the home-registry-secrets-init unit
  # below).
  effectiveEnvFile =
    if cfg.environmentFile != null
    then cfg.environmentFile
    else "${cfg.dataDir}/secrets/home-registry-env";
  # Generated env file holding the composed DATABASE_URL for the app
  # container (see the home-registry-app-env-init unit below).
  appEnvFile = "${cfg.dataDir}/secrets/home-registry-app-env";
in
{
  options.vexos.server.home-registry = {
    enable = lib.mkEnableOption "Home Registry home inventory tracker";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8210;
      description = "Host port for the Home Registry app container.";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/home-registry";
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
        shared by both the home-registry and home-registry-db containers.
        Leave unset (the default) to have a random password generated
        automatically on first activation at
        dataDir/secrets/home-registry-env — no manual secret setup required.
        Set this explicitly only to manage the password through another
        backend (e.g. sops-nix).
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open the firewall for Home Registry's port.";
    };
  };

  config = lib.mkMerge [
  (lib.mkIf cfg.enable {
    # Not postgres/ — live pgdata is not file-backup-safe; the nightly
    # dump below is what actually captures the database.
    vexos.server.backup.servicePaths.home-registry = [ "${cfg.dataDir}/dump" ];

    virtualisation.docker.enable = lib.mkDefault true;
    virtualisation.oci-containers.backend = lib.mkDefault "docker";

    # Dedicated Docker network so home-registry can resolve home-registry-db
    # by container name (Docker's embedded DNS only works on user-defined
    # networks, not the default bridge). Idempotent — safe to re-run.
    systemd.services."home-registry-network" = {
      description   = "Create dedicated Docker network for the Home Registry stack";
      wantedBy      = [ "multi-user.target" ];
      after         = [ "docker.service" ];
      requires      = [ "docker.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        ${pkgs.docker}/bin/docker network inspect home-registry-net >/dev/null 2>&1 || \
          ${pkgs.docker}/bin/docker network create home-registry-net
      '';
    };

    # Auto-generates the Postgres password on first activation when the
    # operator hasn't supplied their own environmentFile — this is what
    # makes vexos.server.home-registry.enable = true; sufficient on its own,
    # with no manual secret creation required.
    systemd.services."home-registry-secrets-init" = lib.mkIf (cfg.environmentFile == null) {
      description   = "Generate Home Registry Postgres password on first activation";
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
    # published ghcr.io/victorytek/home-registry:beta image reads only a
    # single composed DATABASE_URL and ignores discrete POSTGRES_* vars. Its
    # parser requires the literal postgres:// prefix, splits on '@', ':' and
    # '/', and does NOT percent-decode — so the password is used verbatim
    # and must not contain those characters (the unit fails loudly if it
    # does; auto-generated hex passwords are always safe). The password only
    # exists at runtime in effectiveEnvFile, so this unit composes the URL
    # into a second env file for the app container. Once an image containing
    # upstream commit 4c9dfc4 (discrete POSTGRES_* support) is built and
    # published, this unit and appEnvFile can be dropped and the app
    # container can take POSTGRES_HOST/PORT/USER/DB in `environment` plus
    # effectiveEnvFile again. Runs on every start so a rotated password is
    # picked up.
    systemd.services."home-registry-app-env-init" = {
      description   = "Compose DATABASE_URL for the Home Registry app container";
      wantedBy      = [ "multi-user.target" ];
      after         = [ "docker-home-registry-db.service" ] ++ lib.optional (cfg.environmentFile == null) "home-registry-secrets-init.service";
      requires      = [ "docker-home-registry-db.service" ] ++ lib.optional (cfg.environmentFile == null) "home-registry-secrets-init.service";
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
        case "$pw" in
          *@*|*:*|*/*)
            echo "POSTGRES_PASSWORD contains '@', ':' or '/', which the home-registry image's unencoded DATABASE_URL parser cannot handle" >&2
            exit 1
            ;;
        esac
        umask 077
        printf 'DATABASE_URL=postgres://postgres:%s@home-registry-db:5432/home_inventory\n' "$pw" > "${appEnvFile}"

        # docker-home-registry-db.service reports "active" the instant
        # `docker run` forks (docker backend has no sd_notify), well before
        # the postgres entrypoint finishes initdb and starts listening. The
        # Home Registry binary doesn't retry a failed DB connection itself,
        # so without this wait it crash-loops (via systemd's own
        # Restart=on-failure) until Postgres catches up. Block here instead,
        # since this unit already gates docker-home-registry.service via
        # Requires above.
        for i in $(seq 1 60); do
          ${pkgs.docker}/bin/docker exec home-registry-db pg_isready >/dev/null 2>&1 && exit 0
          sleep 1
        done
        echo "home-registry-db did not become ready within 60s" >&2
        exit 1
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

    virtualisation.oci-containers.containers.home-registry-db = {
      image = "postgres:17";
      environment = {
        POSTGRES_USER = "postgres";
        POSTGRES_DB   = "home_inventory";
      };
      environmentFiles = [ effectiveEnvFile ];
      volumes = [
        "${cfg.dataDir}/postgres:/var/lib/postgresql/data"
      ];
      extraOptions = [ "--network=home-registry-net" ];
    };

    virtualisation.oci-containers.containers.home-registry = {
      image = "ghcr.io/victorytek/home-registry:beta";
      ports = [ "${toString cfg.port}:8210" ];
      environment = {
        PORT     = "8210";
        RUST_LOG = "info";
      };
      environmentFiles = [ appEnvFile ];
      extraOptions = [ "--network=home-registry-net" ];
      dependsOn = [ "home-registry-db" ];
    };

    systemd.services."docker-home-registry-db".after    = [ "home-registry-network.service" ] ++ lib.optional (cfg.environmentFile == null) "home-registry-secrets-init.service";
    systemd.services."docker-home-registry-db".requires = [ "home-registry-network.service" ] ++ lib.optional (cfg.environmentFile == null) "home-registry-secrets-init.service";
    systemd.services."docker-home-registry".after       = [ "home-registry-network.service" "home-registry-app-env-init.service" ];
    systemd.services."docker-home-registry".requires    = [ "home-registry-network.service" "home-registry-app-env-init.service" ];

    networking.firewall.allowedTCPPorts = lib.optional cfg.openFirewall cfg.port;
  })

  # Nightly SQL dump — the live postgres/ data directory is not safe to
  # file-backup directly, so the servicePaths entry above only backs up dump/.
  (lib.mkIf cfg.enable (dumpTimer.mkDumpTimer {
    name        = "home-registry";
    container   = "home-registry-db";
    command     = "pg_dump -U postgres home_inventory";
    outputPath  = "${cfg.dataDir}/dump/home-registry.sql";
    description = "Dump Home Registry PostgreSQL database for backup";
  }))
  ];
}
