# modules/lib/dump-timer.nix
# Shared helper: generates the nightly "dump this container's database to a
# plain SQL file" oneshot + timer that a containerised app-plus-db service
# needs, because a live Postgres/MariaDB data directory is not safe to
# file-backup directly. The dump file is what the service registers in
# vexos.server.backup.servicePaths.
#
# Usage in a service module:
#   dumpTimer = import ../lib/dump-timer.nix { inherit lib pkgs; };
#   config = lib.mkIf cfg.enable (lib.mkMerge [
#     { ... }
#     (dumpTimer.mkDumpTimer {
#       name       = "joplin";
#       container  = "joplin-db";
#       command    = ''pg_dump -U joplin joplin'';
#       outputPath = "${cfg.dataDir}/dump/joplin.sql";
#     })
#   ]);
#
# Scheduling: dumps land in the `hour` window (default 23), ahead of restic's
# default "daily" (~00:00) run, so a fresh dump exists before the backup reads
# it. The minute is derived from a hash of `name` rather than hand-picked, so
# two services can't silently collide on the same wall-clock second and no
# module author has to know what times are already taken. The derived minute is
# constrained to 0-44, leaving at least 15 minutes of headroom before a
# midnight backup run. Pass offsetMinute explicitly to pin a specific time.
#
# If vexos.server.backup.timerConfig is customised to run earlier than this
# window, the dump picked up by that run may be one cycle stale.
{ lib, pkgs }:
let
  hexValue = {
    "0" = 0; "1" = 1; "2" = 2;  "3" = 3;  "4" = 4;  "5" = 5;  "6" = 6;  "7" = 7;
    "8" = 8; "9" = 9; "a" = 10; "b" = 11; "c" = 12; "d" = 13; "e" = 14; "f" = 15;
  };

  # First 6 hex digits of sha256(name) as an integer — enough spread for a
  # mod-45 bucket, and well inside Nix's integer range.
  hashToInt = name:
    lib.foldl' (acc: c: acc * 16 + hexValue.${c}) 0
      (lib.stringToCharacters
        (builtins.substring 0 6 (builtins.hashString "sha256" name)));
in
{
  mkDumpTimer =
    { name                                             # service identity; seeds the offset hash
    , container                                        # container to exec the dump in
    , command                                          # dump command, run inside the container
    , outputPath                                       # host path the SQL dump is written to
    , envFile ? null                                   # sourced before the dump, for credentials
    , backend ? "docker"                               # "docker" or "podman"
    , hour ? 23                                        # dump window hour
    , offsetMinute ? null                              # null = derive from hash of `name`
    , unitName ? "${name}-dump"
    , description ? "Dump ${name} database for backup"
    }:
    let
      minute = if offsetMinute != null then offsetMinute else lib.mod (hashToInt name) 45;
      cli = if backend == "podman" then "${pkgs.podman}/bin/podman" else "${pkgs.docker}/bin/docker";
      containerUnit = "${backend}-${container}.service";
    in
    {
      systemd.services.${unitName} = {
        inherit description;
        after    = [ containerUnit ];
        requires = [ containerUnit ];
        serviceConfig.Type = "oneshot";
        script = lib.concatStringsSep "\n" (
          lib.optional (envFile != null) ''source "${envFile}"''
          ++ [ ''${cli} exec ${container} ${command} > "${outputPath}"'' ]
        );
      };

      systemd.timers.${unitName} = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "*-*-* ${lib.fixedWidthNumber 2 hour}:${lib.fixedWidthNumber 2 minute}:00";
          Persistent = true;
        };
      };
    };
}
