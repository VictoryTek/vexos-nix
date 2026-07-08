# modules/server/joplin.nix
# Joplin Server — self-hosted sync target for Joplin desktop/mobile clients.
# No nixpkgs package or NixOS module exists for Joplin Server (only the
# joplin-desktop client is packaged), so it is deployed as a two-container
# OCI stack: joplin-server (the app) + joplin-db (dedicated postgres:16),
# talking to each other over an isolated Docker network. The dedicated
# Postgres instance is intentional — it avoids opening the host's shared
# Postgres to the Docker bridge network for a service this repo has no
# other native-Postgres consumer for. See:
#   .github/docs/subagent_docs/joplin_server_spec.md
#
# Exposure: Tailscale tailnet only. The firewall rule is scoped to the
# tailscale0 interface (services.tailscale is enabled unconditionally in
# modules/network.nix), not the global allowed-ports list. There is no
# reverse proxy / TLS in front of this service — Tailscale's WireGuard
# tunnel is the transport security boundary.
#
# No required configuration — vexos.server.joplin.enable = true; is enough:
#   - The Postgres password is generated automatically on first activation
#     and stored at dataDir/secrets/joplin-env (0600, root-only). Set
#     vexos.server.joplin.environmentFile yourself only if you want to
#     manage the secret through another backend (e.g. sops-nix).
#   - baseUrl defaults to "http://<networking.hostName>:<port>", which
#     resolves correctly over Tailscale MagicDNS for most tailnets (MagicDNS
#     adds the tailnet's DNS search domain, so the bare hostname resolves
#     without needing the full "<hostname>.<tailnet>.ts.net" form). Override
#     it if your tailnet needs the fully-qualified name instead.
#
# First login: admin@localhost / admin (Joplin's published defaults) — the
# service is Tailscale-only, but changing this from the web UI after first
# boot is still recommended.
#
# Backup: the live Postgres data directory is not file-backup-safe, so a
# nightly `pg_dump` writes a plain SQL dump to dataDir/dump, which is what
# modules/server/backup.nix's servicePaths entry actually backs up.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.joplin;
  # If the operator doesn't supply their own secret backend, generate one
  # locally on first activation (see the joplin-secrets-init unit below).
  effectiveEnvFile =
    if cfg.environmentFile != null
    then cfg.environmentFile
    else "${cfg.dataDir}/secrets/joplin-env";
in
{
  options.vexos.server.joplin = {
    enable = lib.mkEnableOption "Joplin Server note sync";

    port = lib.mkOption {
      type = lib.types.port;
      default = 22300;
      description = "Host port for the Joplin Server app container.";
    };

    baseUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://${config.networking.hostName}:${toString cfg.port}";
      description = ''
        URL Joplin clients use to reach this server. Used by Joplin Server
        to validate request origins — a mismatch causes "invalid origin"
        sync errors. Defaults to the host's bare hostname, which resolves
        correctly over Tailscale MagicDNS for most tailnets. Override with
        the fully-qualified MagicDNS name (e.g.
        "http://myhost.tailnet-name.ts.net:22300") or a tailnet IP if the
        bare hostname doesn't resolve on your tailnet.
      '';
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/joplin-server";
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
        shared by both the joplin-server and joplin-db containers. Leave unset
        (the default) to have a random password generated automatically on
        first activation at dataDir/secrets/joplin-env — no manual secret
        setup required. Set this explicitly only to manage the password
        through another backend (e.g. sops-nix).
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Open Joplin Server's port on the tailscale0 interface only (not the
        global allowed-ports list) — this service is Tailscale-only by design.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.docker.enable = lib.mkDefault true;
    virtualisation.oci-containers.backend = "docker";

    # Dedicated Docker network so joplin-server can resolve joplin-db by
    # container name (Docker's embedded DNS only works on user-defined
    # networks, not the default bridge). Idempotent — safe to re-run.
    systemd.services."joplin-network" = {
      description   = "Create dedicated Docker network for the Joplin Server stack";
      wantedBy      = [ "multi-user.target" ];
      after         = [ "docker.service" ];
      requires      = [ "docker.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        ${pkgs.docker}/bin/docker network inspect joplin-net >/dev/null 2>&1 || \
          ${pkgs.docker}/bin/docker network create joplin-net
      '';
    };

    # Auto-generates the Postgres password on first activation when the
    # operator hasn't supplied their own environmentFile — this is what
    # makes vexos.server.joplin.enable = true; sufficient on its own, with
    # no manual secret creation required.
    systemd.services."joplin-secrets-init" = lib.mkIf (cfg.environmentFile == null) {
      description   = "Generate Joplin Server Postgres password on first activation";
      wantedBy      = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        install -d -m 0700 "${cfg.dataDir}/secrets"
        if [ ! -f "${effectiveEnvFile}" ]; then
          echo "POSTGRES_PASSWORD=$(${pkgs.openssl}/bin/openssl rand -hex 24)" > "${effectiveEnvFile}"
          chmod 0600 "${effectiveEnvFile}"
        fi
      '';
    };

    # No tmpfiles rule for dataDir/postgres: the postgres:16 image's root
    # entrypoint chowns PGDATA to its own UID on first run and expects to
    # own it thereafter. A "d ... root root" rule here would re-assert
    # root:root ownership on every activation (systemd-tmpfiles --create
    # runs on every nixos-rebuild switch), stripping access from the
    # already-running container without restarting it.
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0700 root root -"
      "d ${cfg.dataDir}/dump 0700 root root -"
    ];

    virtualisation.oci-containers.containers.joplin-db = {
      image = "postgres:16";
      environment = {
        POSTGRES_USER = "joplin";
        POSTGRES_DB   = "joplin";
      };
      environmentFiles = [ effectiveEnvFile ];
      volumes = [
        "${cfg.dataDir}/postgres:/var/lib/postgresql/data"
      ];
      extraOptions = [ "--network=joplin-net" ];
    };

    virtualisation.oci-containers.containers.joplin-server = {
      image = "joplin/server:latest";
      ports = [ "${toString cfg.port}:22300" ];
      environment = {
        APP_PORT          = "22300";
        APP_BASE_URL      = cfg.baseUrl;
        DB_CLIENT         = "pg";
        POSTGRES_DATABASE = "joplin";
        POSTGRES_USER     = "joplin";
        POSTGRES_PORT     = "5432";
        POSTGRES_HOST     = "joplin-db";
      };
      environmentFiles = [ effectiveEnvFile ];
      extraOptions = [ "--network=joplin-net" ];
      dependsOn = [ "joplin-db" ];
    };

    systemd.services."docker-joplin-db".after    = [ "joplin-network.service" ] ++ lib.optional (cfg.environmentFile == null) "joplin-secrets-init.service";
    systemd.services."docker-joplin-db".requires = [ "joplin-network.service" ] ++ lib.optional (cfg.environmentFile == null) "joplin-secrets-init.service";
    systemd.services."docker-joplin-server".after    = [ "joplin-network.service" ] ++ lib.optional (cfg.environmentFile == null) "joplin-secrets-init.service";
    systemd.services."docker-joplin-server".requires = [ "joplin-network.service" ] ++ lib.optional (cfg.environmentFile == null) "joplin-secrets-init.service";

    # Nightly SQL dump — the live postgres/ data directory is not safe to
    # file-backup directly, so backup.nix's servicePaths only backs up dump/.
    # Scheduled at 23:30 so a fresh dump exists before restic's default
    # "daily" (~00:00) run reads it; if vexos.server.backup.timerConfig is
    # customized to run earlier than 23:30, the dump may be one cycle stale.
    systemd.services."joplin-postgres-dump" = {
      description = "Dump Joplin PostgreSQL database for backup";
      after    = [ "docker-joplin-db.service" ];
      requires = [ "docker-joplin-db.service" ];
      serviceConfig.Type = "oneshot";
      script = ''
        ${pkgs.docker}/bin/docker exec joplin-db pg_dump -U joplin joplin > "${cfg.dataDir}/dump/joplin.sql"
      '';
    };

    systemd.timers."joplin-postgres-dump" = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 23:30:00";
        Persistent = true;
      };
    };

    networking.firewall.interfaces.tailscale0.allowedTCPPorts =
      lib.optional cfg.openFirewall cfg.port;
  };
}
