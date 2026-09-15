# modules/server/nas-sync.nix
# Scheduled rsync mirror jobs between mounted NAS paths — the declarative
# replacement for a manual VM + Grsync session.
#
# Each entry in vexos.server.nasSync.jobs.<name> becomes a
# "nas-sync-<name>.service" / ".timer" pair that runs:
#
#   rsync -a [--delete] --partial --protect-args -v <source> <destination>
#
# -a (archive) covers preserve time/permissions/owner/group; --delete mirrors
# deletions (gated by deleteOnDestination); --partial keeps partially
# transferred files; --protect-args is a no-op for local paths but kept for
# parity with the source Grsync session. "Show transfer progress" is
# deliberately NOT translated to --progress: that flag is for an interactive
# terminal, and under systemd it would just bloat the journal — -v already
# logs each file transferred.
#
# Both source and destination are host-specific mount paths (e.g. two
# separately mounted NAS shares) declared elsewhere — via
# vexos.storage.remote (modules/storage-remote.nix) or a plain fileSystems
# entry — and referenced by mediaMounts so the job waits for (and, for
# automount-based remote mounts, correctly triggers) both mounts instead of
# racing them.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.nasSync;
  storageMounts = import ../lib/storage-mount-ordering.nix { inherit lib; };

  jobModule = lib.types.submodule {
    options = {
      source = lib.mkOption {
        type = lib.types.str;
        example = "/goliath/data/media/tv/";
        description = ''
          rsync source path. Include or omit the trailing slash exactly as
          you want rsync to interpret it (trailing slash = copy directory
          *contents*; no trailing slash = copy the directory itself) — this
          module passes the string through unchanged.
        '';
      };

      destination = lib.mkOption {
        type = lib.types.str;
        example = "/megatron/data/media/tv/";
        description = "rsync destination path. Same trailing-slash rule as source.";
      };

      deleteOnDestination = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Mirror deletions: remove files from destination that no longer
          exist in source (rsync --delete). Set false for a one-way
          accumulate-only copy.
        '';
      };

      extraRsyncOptions = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Additional raw rsync flags appended to the command.";
      };

      mediaMounts = storageMounts.mediaMountsOption;

      timerConfig = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = { OnCalendar = "daily"; Persistent = true; };
        description = "systemd timer schedule for this sync job.";
      };
    };
  };
in
{
  options.vexos.server.nasSync = {
    enable = lib.mkEnableOption "scheduled rsync mirror jobs between mounted NAS paths";

    jobs = lib.mkOption {
      type = lib.types.attrsOf jobModule;
      default = { };
      description = ''
        Named rsync mirror jobs. Each key becomes a
        "nas-sync-<name>.service"/".timer" pair. Populate per-host in
        server-services.nix, e.g.:

          vexos.server.nasSync.jobs.tv = {
            source = "/goliath/data/media/tv/";
            destination = "/megatron/data/media/tv/";
            mediaMounts = [ "/goliath" "/megatron" ];
          };
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services = lib.mapAttrs' (name: job: lib.nameValuePair "nas-sync-${name}" {
      description = "rsync mirror: ${name}";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.concatStringsSep " " ([
          "${pkgs.rsync}/bin/rsync"
          "-a"
        ] ++ lib.optional job.deleteOnDestination "--delete" ++ [
          "--partial"
          "--protect-args"
          "-v"
        ] ++ [ (lib.escapeShellArgs ([ job.source job.destination ] ++ job.extraRsyncOptions)) ]);
        Nice = 19;
        IOSchedulingClass = "idle";
      };
      onFailure = [ "notify-failure@nas-sync-${name}.service" ];
      unitConfig = storageMounts.requiresMountsFor job.mediaMounts;
    }) cfg.jobs;

    systemd.timers = lib.mapAttrs' (name: job: lib.nameValuePair "nas-sync-${name}" {
      description = "Run nas-sync-${name}.service on schedule";
      wantedBy = [ "timers.target" ];
      timerConfig = job.timerConfig;
    }) cfg.jobs;
  };
}
