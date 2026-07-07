# modules/server/backup.nix
# Declarative restic backups — opt-in. Automatically backs up the data
# directories of whichever vexos.server.<x> services are enabled, so adding
# a new service doesn't require manually maintaining a separate backup list.
#
# Repository target (local disk, SFTP, B2, etc.) is entirely up to the user —
# see vexos.server.backup.repository / repositoryFile.
{ config, lib, ... }:
let
  cfg = config.vexos.server.backup;

  # Default data directory per enabled service. Most NixOS services follow the
  # StateDirectory convention of /var/lib/<service-name>; a few exceptions are
  # called out below. Keep in sync with justfile's _server_service_names.
  #
  # Deliberately excluded:
  #   syncthing — its dataDir (syncthing.nix) is the *entire* user home
  #               directory, not a scoped data folder; auto-including it would
  #               silently make "enable syncthing" imply "back up the whole
  #               home directory". Add it via extraPaths if that's wanted.
  servicePaths = {
    adguard          = [ "/var/lib/adguardhome" ];
    arr              = [ "/var/lib/sonarr" "/var/lib/radarr" "/var/lib/lidarr" "/var/lib/prowlarr" "/var/lib/sabnzbd" ];
    attic            = [ config.vexos.server.attic.dataDir ];
    audiobookshelf   = [ "/var/lib/audiobookshelf" ];
    authelia         = [ "/var/lib/authelia" ];
    caddy            = [ "/var/lib/caddy" ];
    cockpit          = [ ];
    code-server      = [ ];
    dockhand         = [ config.vexos.server.dockhand.dataDir ];
    dozzle           = [ ];
    forgejo          = [ "/var/lib/forgejo" ];
    grafana          = [ "/var/lib/grafana" ];
    headscale        = [ "/var/lib/headscale" ];
    home-assistant   = [ "/var/lib/hass" ];
    homepage         = [ "/var/lib/homepage" ];
    immich           = [ "/var/lib/immich" ];
    jellyfin         = [ "/var/lib/jellyfin" ];
    joplin           = [ "${config.vexos.server.joplin.dataDir}/dump" ]; # not postgres/ — live pgdata isn't file-backup-safe
    kavita           = [ "/var/lib/kavita" ];
    kiji-proxy       = [ ];
    komga            = [ "/var/lib/komga" ];
    listmonk         = [ "/var/lib/listmonk" ];
    loki             = [ "/var/lib/loki" ];
    matrix-conduit   = [ "/var/lib/matrix-conduit" ];
    mealie           = [ "/var/lib/mealie" ];
    minio            = [ "/var/lib/minio" ];
    nas              = [ ];
    navidrome        = [ "/var/lib/navidrome" ];
    netdata          = [ ];
    nextcloud        = [ "/var/lib/nextcloud" ];
    node-red         = [ "/var/lib/node-red" ];
    ntfy             = [ "/var/lib/ntfy-sh" ];
    paperless        = [ "/var/lib/paperless" ];
    papermc          = [ "/var/lib/minecraft" ];
    photoprism       = [ "/var/lib/photoprism" ];
    plex             = [ "/var/lib/plex" ];
    portainer        = [ "/var/lib/portainer" ];
    portbook         = [ "/var/lib/portbook" ];
    prometheus       = [ "/var/lib/prometheus2" ];
    proxmox          = [ "/var/lib/pve-cluster" "/etc/pve" ];
    rustdesk         = [ "/var/lib/rustdesk-server" ];
    scrutiny         = [ "/var/lib/scrutiny" ];
    seerr            = [ "/var/lib/seerr" ];
    stirling-pdf     = [ ];
    tautulli         = [ "/var/lib/tautulli" ];
    uptime-kuma      = [ "/var/lib/uptime-kuma" ];
    vaultwarden      = [ "/var/lib/vaultwarden" ];
    vexboard         = [ "/var/lib/vexboard" ];
    zigbee2mqtt      = [ "/var/lib/zigbee2mqtt" ];
  };

  enabledServicePaths = lib.flatten (
    lib.mapAttrsToList
      (name: paths: lib.optionals (config.vexos.server.${name}.enable or false) paths)
      servicePaths
  );

  postgresDumpFile = "/var/backup/postgresql-dump.sql";
in
{
  options.vexos.server.backup = {
    enable = lib.mkEnableOption "Declarative restic backups of enabled server services";

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
        Use this for services excluded from the automatic table (e.g. syncthing)
        or any other data not covered above.
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

  config = lib.mkIf cfg.enable {
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

    services.restic.backups.main = {
      inherit (cfg) repository repositoryFile pruneOpts timerConfig;
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
  };
}
