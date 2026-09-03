# modules/server/backup.nix
# Declarative restic backups — opt-in. Automatically backs up the data
# directories of whichever vexos.server.<x> services are enabled.
#
# Registration is decentralized: each service module declares its own backup
# paths in its own file via
#
#   vexos.server.backup.servicePaths.<name> = [ "/var/lib/<name>" ];
#
# inside its `config = lib.mkIf cfg.enable { ... }` block. There is no central
# table here to keep in sync, and the assertion below makes forgetting the line
# a build failure rather than a service that silently has no backup coverage.
#
# Repository target (local disk, SFTP, B2, etc.) is entirely up to the user —
# see vexos.server.backup.repository / repositoryFile.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.backup;

  # Services that correctly have no backup paths. Membership here is the
  # explicit "this service has nothing worth backing up" statement that
  # satisfies the assertion below. Every entry needs a reason.
  noBackupNeeded = [
    # ── Not a data service ───────────────────────────────────────────────
    "backup"          # this module itself
    "docker"          # container runtime
    "podman"          # container runtime
    "proxy"           # generates Caddy virtualHosts; holds no state of its own
    "nas"             # umbrella toggle over cockpit + plugins + backend selector

    # ── Stateless, or derived state only ─────────────────────────────────
    "alertmanager"    # silences/nflog are transient operational state
    "cloudflare-ddns" # polls public IP and writes to Cloudflare's API; no local state
    "cockpit"         # web UI over the host; no state of its own
    "code-server"     # workspace lives in the user's home, backed up separately
    "dozzle"          # log viewer over the container socket; stateless
    "fluent-bit"      # /var/lib/fluent-bit holds only a systemd log cursor
    "kernelBuilder"   # GC roots for derived build artifacts; rebuildable
    "kiji-proxy"      # stateless proxy
    "netdata"         # metrics; Prometheus/Loki are the durable stores
    "nginx"           # config is declarative; certs live in /var/lib/acme
    "searxng"         # config is declarative; no persistent user data
    "stirling-pdf"    # documents are processed in-flight, not stored
    "unbound"         # cache + regenerable DNSSEC trust anchor

    # ── Deliberately excluded ────────────────────────────────────────────
    # syncthing's dataDir (syncthing.nix) is the *entire* user home
    # directory, not a scoped data folder; auto-including it would silently
    # make "enable syncthing" imply "back up the whole home directory".
    # Add it via vexos.server.backup.extraPaths if that's actually wanted.
    "syncthing"
  ];

  enabledServicePaths = lib.flatten (
    lib.mapAttrsToList
      (name: paths: lib.optionals (config.vexos.server.${name}.enable or false) paths)
      cfg.servicePaths
  );

  # Enabled services that have registered backup paths, sorted (lib.attrNames is
  # lexicographic — keeps the tag argument list stable across rebuilds).
  enabledBackupServices = lib.filter
    (name: config.vexos.server.${name}.enable or false)
    (lib.attrNames cfg.servicePaths);

  # Service -> paths for the services actually present in each snapshot. Consumed
  # by `just restore-service <name>`. extraPaths and the postgres dump are
  # deliberately excluded: they are not service-scoped.
  backupPathsManifest = lib.filterAttrs
    (name: _: config.vexos.server.${name}.enable or false)
    cfg.servicePaths;

  # Enabled services that neither registered backup paths nor declared
  # themselves stateless. See the assertion below.
  unregisteredServices = lib.filter
    (name:
      (config.vexos.server.${name}.enable or false)
      && !(lib.hasAttr name cfg.servicePaths)
      && !(lib.elem name noBackupNeeded))
    (builtins.attrNames config.vexos.server);

  postgresDumpFile = "/var/backup/postgresql-dump.sql";
in
{
  options.vexos.server.backup = {
    enable = lib.mkEnableOption "Declarative restic backups of enabled server services";

    servicePaths = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf lib.types.str);
      default = { };
      example = lib.literalExpression ''{ mealie = [ "/var/lib/mealie" ]; }'';
      description = ''
        Per-service backup paths, keyed by the service's vexos.server.<name>
        attribute. Set by each service module in its own file rather than
        centrally here, so backup coverage lives next to the service
        definition it describes.

        A service's paths are only included in the backup when
        vexos.server.<name>.enable is true, so registering unconditionally
        inside the module's own enable guard is correct.

        Every enabled vexos.server.<name> must either appear here or be listed
        in backup.nix's noBackupNeeded list — otherwise the build fails.
      '';
    };

    repository = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Restic repository to back up to, e.g. "sftp:backup@host:/backups/vexos"
        or "/mnt/backup-drive/restic-repo". Mutually exclusive with repositoryFile.
      '';
    };

    repositoryFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to a file containing the restic repository location.";
    };

    passwordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to a file containing the restic repository password.";
    };

    extraPaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Additional paths to back up beyond the automatic per-service defaults.
        Use this for services excluded from automatic registration (e.g.
        syncthing) or any other data not covered above.
      '';
    };

    pruneOpts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "--keep-daily 7" "--keep-weekly 4" "--keep-monthly 6" ];
      description = "restic forget --prune retention policy.";
    };

    timerConfig = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { OnCalendar = "daily"; Persistent = true; };
      description = "systemd timer schedule for the backup run.";
    };
  };

  config = lib.mkMerge [
    # Deliberately NOT gated on cfg.enable: the guarantee is "every service
    # module declares its backup intent", which has to hold on hosts that
    # haven't turned restic on too — otherwise the check is only active where
    # it is least needed, and a new module's missing registration is found
    # long after it was written.
    {
      assertions = [
        {
          assertion = unregisteredServices == [ ];
          message = ''
            These enabled services have not registered backup paths:
              ${lib.concatStringsSep ", " unregisteredServices}

            Add to the service's own module, inside its config = lib.mkIf cfg.enable block:
              vexos.server.backup.servicePaths.<name> = [ "/var/lib/<name>" ];

            If the service genuinely has no state worth backing up, add its
            name (with a reason) to noBackupNeeded in modules/server/backup.nix.
          '';
        }
      ];
    }

    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = cfg.repository != null || cfg.repositoryFile != null;
          message = "vexos.server.backup.repository or repositoryFile must be set.";
        }
        {
          assertion = cfg.passwordFile != null;
          message = "vexos.server.backup.passwordFile must be set.";
        }
      ];

      # jq parses /etc/vexos/backup-paths.json in the restore-service recipe.
      environment.systemPackages = [ pkgs.jq ];

      # Records which data paths belong to which service, so a per-service
      # restore does not have to re-derive them. Only enabled services appear —
      # matching exactly what each snapshot contains.
      environment.etc."vexos/backup-paths.json".text =
        builtins.toJSON backupPathsManifest;

      services.restic.backups.main = {
        inherit (cfg) repository repositoryFile pruneOpts timerConfig;
        # Tag every snapshot with "vexos" plus one tag per service it covers, so
        # `restic-main snapshots --tag <service>` and `restic-main restore
        # latest --tag <service>` can select by service. The nixpkgs restic
        # module has no `tags` option — tags go through extraBackupArgs.
        extraBackupArgs =
          lib.concatMap (t: [ "--tag" t ]) ([ "vexos" ] ++ enabledBackupServices);
        # Upstream defaults this to false; without it, a fresh repository is
        # never created and every backup run fails with "repository does not
        # exist". `restic cat config || restic init` is a no-op once the repo
        # already exists, so this is safe to leave on unconditionally.
        initialize = true;
        # Upstream passwordFile is typed `nullOr str`, not `path` — convert so our
        # nicer path-typed option (catches typos at eval time) still fits.
        passwordFile = lib.mkIf (cfg.passwordFile != null) (toString cfg.passwordFile);
        paths = enabledServicePaths ++ cfg.extraPaths
          ++ lib.optional config.services.postgresql.enable postgresDumpFile;
        backupPrepareCommand = lib.mkIf config.services.postgresql.enable ''
          install -d -m 0700 -o postgres -g postgres "$(dirname "${postgresDumpFile}")"
          sudo -u postgres pg_dumpall > "${postgresDumpFile}"
        '';
        backupCleanupCommand = lib.mkIf config.services.postgresql.enable ''
          rm -f "${postgresDumpFile}"
        '';
      };

      systemd.services."restic-backups-main".onFailure = [ "notify-failure@backup.service" ];
    })
  ];
}
