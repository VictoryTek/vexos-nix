# Grimmory — self-hosted digital library for ebooks, comics, and audiobooks.
# No nixpkgs package or NixOS module exists for Grimmory, so it is deployed as a
# two-container OCI stack: grimmory (the app) + grimmory-db (dedicated
# lscr.io/linuxserver/mariadb), talking to each other over an isolated Docker
# network. Mirrors modules/server/joplin.nix, this repo's other two-container
# OCI service. See:
#   .github/docs/subagent_docs/grimmory_server_spec.md
#
# No required configuration — vexos.server.grimmory.enable = true; is enough:
#   - MariaDB credentials are generated automatically on first activation and
#     stored at dataDir/secrets/grimmory-env (0600, root-only). Set
#     vexos.server.grimmory.environmentFile yourself only if you want to manage
#     the secret through another backend (e.g. sops-nix).
#   - libraryDir/bookdropDir default under dataDir but can be pointed at
#     existing storage (e.g. a mergerfs/storage-remote pool) if desired.
#
# First run: visit the web UI and create the admin account yourself — Grimmory
# has no published default credentials to change (unlike Joplin/Vaultwarden).
# Since openFirewall defaults to true (LAN-reachable, matching Komga/Kavita),
# claim the admin account promptly after enabling.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.grimmory;
  effectiveEnvFile =
    if cfg.environmentFile != null
    then cfg.environmentFile
    else "${cfg.dataDir}/secrets/grimmory-env";
in
{
  options.vexos.server.grimmory = {
    enable = lib.mkEnableOption "Grimmory ebook/comic/audiobook library server";

    port = lib.mkOption {
      type = lib.types.port;
      default = 6060;
      description = "Host port for the Grimmory app container.";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/grimmory";
      description = ''
        Host directory for the app's own state (dataDir/app-data), the
        MariaDB config/data directory (dataDir/mariadb-config), the nightly
        SQL dump (dataDir/dump), and the auto-generated secrets file
        (dataDir/secrets).
      '';
    };

    libraryDir = lib.mkOption {
      type = lib.types.str;
      default = "${cfg.dataDir}/books";
      description = ''
        Host path bind-mounted to /books — the permanent ebook/comic/audiobook
        library. Override to point at existing storage (e.g. a mergerfs or
        storage-remote pool) instead of the dataDir-relative default.
      '';
    };

    bookdropDir = lib.mkOption {
      type = lib.types.str;
      default = "${cfg.dataDir}/bookdrop";
      description = ''
        Host path bind-mounted to /bookdrop — the watched auto-import staging
        folder. Files dropped here are enriched with metadata and queued for
        review before being moved into libraryDir.
      '';
    };

    userId = lib.mkOption {
      type = lib.types.int;
      default = 1000;
      description = ''
        Passed as USER_ID (app container) and PUID (db container). Also used
        to pre-create app-data/libraryDir/bookdropDir with matching
        ownership, since the app image (unlike the LinuxServer.io db image)
        does not self-chown its mounts.
      '';
    };

    groupId = lib.mkOption {
      type = lib.types.int;
      default = 1000;
      description = "Passed as GROUP_ID (app container) and PGID (db container).";
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Optional systemd EnvironmentFile supplying DATABASE_PASSWORD,
        MYSQL_PASSWORD (same value, shared by both containers), and
        MYSQL_ROOT_PASSWORD. Leave unset (the default) to have random
        passwords generated automatically on first activation at
        dataDir/secrets/grimmory-env — no manual secret setup required. Set
        this explicitly only to manage the secret through another backend
        (e.g. sops-nix).
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open the firewall for Grimmory's port.";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.docker.enable = lib.mkDefault true;
    virtualisation.oci-containers.backend = lib.mkDefault "docker";

    # Dedicated Docker network so grimmory can resolve grimmory-db by
    # container name (Docker's embedded DNS only works on user-defined
    # networks, not the default bridge). Idempotent — safe to re-run.
    systemd.services."grimmory-network" = {
      description   = "Create dedicated Docker network for the Grimmory stack";
      wantedBy      = [ "multi-user.target" ];
      after         = [ "docker.service" ];
      requires      = [ "docker.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        ${pkgs.docker}/bin/docker network inspect grimmory-net >/dev/null 2>&1 || \
          ${pkgs.docker}/bin/docker network create grimmory-net
      '';
    };

    # Auto-generates MariaDB credentials on first activation when the
    # operator hasn't supplied their own environmentFile — this is what
    # makes vexos.server.grimmory.enable = true; sufficient on its own, with
    # no manual secret creation required.
    systemd.services."grimmory-secrets-init" = lib.mkIf (cfg.environmentFile == null) {
      description   = "Generate Grimmory MariaDB credentials on first activation";
      wantedBy      = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        install -d -m 0700 "${cfg.dataDir}/secrets"
        if [ ! -f "${effectiveEnvFile}" ]; then
          dbPass=$(${pkgs.openssl}/bin/openssl rand -hex 24)
          rootPass=$(${pkgs.openssl}/bin/openssl rand -hex 24)
          {
            echo "DATABASE_PASSWORD=$dbPass"
            echo "MYSQL_PASSWORD=$dbPass"
            echo "MYSQL_ROOT_PASSWORD=$rootPass"
          } > "${effectiveEnvFile}"
          chmod 0600 "${effectiveEnvFile}"
        fi
      '';
    };

    # No tmpfiles rule for dataDir/mariadb-config: the linuxserver/mariadb
    # image's s6-init entrypoint chowns /config to its own managed UID/GID
    # (derived from PUID/PGID) on first run and expects to own it
    # thereafter. A "d ... root root" rule here would re-assert root:root
    # ownership on every activation (systemd-tmpfiles --create runs on every
    # nixos-rebuild switch), stripping access from the already-running
    # container without restarting it. Same reasoning as joplin.nix's
    # postgres/ exclusion.
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 root root -"
      "d ${cfg.dataDir}/app-data 0755 ${toString cfg.userId} ${toString cfg.groupId} -"
      "d ${cfg.libraryDir} 0755 ${toString cfg.userId} ${toString cfg.groupId} -"
      "d ${cfg.bookdropDir} 0755 ${toString cfg.userId} ${toString cfg.groupId} -"
      "d ${cfg.dataDir}/dump 0700 root root -"
    ];

    virtualisation.oci-containers.containers.grimmory-db = {
      image = "lscr.io/linuxserver/mariadb:11.4.8";
      environment = {
        PUID           = toString cfg.userId;
        PGID           = toString cfg.groupId;
        TZ             = config.time.timeZone;
        MYSQL_DATABASE = "grimmory";
        MYSQL_USER     = "grimmory";
      };
      environmentFiles = [ effectiveEnvFile ];
      volumes = [
        "${cfg.dataDir}/mariadb-config:/config"
      ];
      extraOptions = [ "--network=grimmory-net" ];
    };

    virtualisation.oci-containers.containers.grimmory = {
      image = "grimmory/grimmory:v0.38.2";
      ports = [ "${toString cfg.port}:6060" ];
      environment = {
        USER_ID            = toString cfg.userId;
        GROUP_ID           = toString cfg.groupId;
        TZ                 = config.time.timeZone;
        DATABASE_URL       = "jdbc:mariadb://grimmory-db:3306/grimmory";
        DATABASE_USERNAME  = "grimmory";
        SWAGGER_ENABLED    = "false";
        FORCE_DISABLE_OIDC = "false";
      };
      environmentFiles = [ effectiveEnvFile ];
      volumes = [
        "${cfg.dataDir}/app-data:/app/data"
        "${cfg.libraryDir}:/books"
        "${cfg.bookdropDir}:/bookdrop"
      ];
      extraOptions = [ "--network=grimmory-net" ];
      dependsOn = [ "grimmory-db" ];
    };

    systemd.services."docker-grimmory-db".after    = [ "grimmory-network.service" ] ++ lib.optional (cfg.environmentFile == null) "grimmory-secrets-init.service";
    systemd.services."docker-grimmory-db".requires = [ "grimmory-network.service" ] ++ lib.optional (cfg.environmentFile == null) "grimmory-secrets-init.service";
    systemd.services."docker-grimmory".after       = [ "grimmory-network.service" ] ++ lib.optional (cfg.environmentFile == null) "grimmory-secrets-init.service";
    systemd.services."docker-grimmory".requires     = [ "grimmory-network.service" ] ++ lib.optional (cfg.environmentFile == null) "grimmory-secrets-init.service";

    # Nightly SQL dump — the live mariadb-config/ data directory is not safe
    # to file-backup directly, so backup.nix's servicePaths entry only backs
    # up dump/ (plus libraryDir, the irreplaceable user media). Scheduled at
    # 23:15 (offset from joplin's 23:30 purely to avoid both dump jobs
    # landing on the exact same wall-clock second) so a fresh dump exists
    # before restic's default "daily" (~00:00) run reads it.
    systemd.services."grimmory-mariadb-dump" = {
      description = "Dump Grimmory MariaDB database for backup";
      after    = [ "docker-grimmory-db.service" ];
      requires = [ "docker-grimmory-db.service" ];
      serviceConfig.Type = "oneshot";
      script = ''
        source "${effectiveEnvFile}"
        ${pkgs.docker}/bin/docker exec grimmory-db mariadb-dump -u root -p"$MYSQL_ROOT_PASSWORD" grimmory > "${cfg.dataDir}/dump/grimmory.sql"
      '';
    };

    systemd.timers."grimmory-mariadb-dump" = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 23:15:00";
        Persistent = true;
      };
    };

    networking.firewall.allowedTCPPorts = lib.optional cfg.openFirewall cfg.port;
  };
}
