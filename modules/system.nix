# modules/system.nix
# General system-level configuration shared across all hosts.
# btrfs snapshot management (snapper), auto-scrub, and related GUI tools are
# enabled by default but can be disabled on non-btrfs hosts (e.g. VM guests)
# by setting vexos.btrfs.enable = false in the host's configuration.
{ pkgs, lib, config, ... }:
let
  cfg = config.vexos.btrfs;
in
{
  options.vexos.btrfs.enable = lib.mkOption {
    type    = lib.types.bool;
    default = true;
    description = ''
      Enable btrfs snapshot management (snapper), auto-scrub, and the
      btrfs-assistant GUI. Set to false on hosts with ext4/xfs root
      filesystems (e.g. VM guests) to avoid installing unneeded packages.
    '';
  };

  config = lib.mkIf cfg.enable {
    # ---------- Snapper (btrfs snapshot management) ----------
    services.snapper.configs = {
      root = {
        SUBVOLUME = "/";
        ALLOW_USERS = [ "nimda" ];
        TIMELINE_CREATE = true;
        TIMELINE_CLEANUP = true;
        TIMELINE_MIN_AGE = 1800;
        TIMELINE_LIMIT_HOURLY = 5;
        TIMELINE_LIMIT_DAILY = 7;
        TIMELINE_LIMIT_WEEKLY = 4;
        TIMELINE_LIMIT_MONTHLY = 3;
        TIMELINE_LIMIT_YEARLY = 0;
        NUMBER_LIMIT = "50";
        NUMBER_LIMIT_IMPORTANT = "10";
      };
    };

    services.snapper.snapshotRootOnBoot = true;
    services.snapper.persistentTimer = true;

    # Create /.snapshots subvolume on first activation.
    # Idempotent — snapper requires this subvolume before its services start.
    system.activationScripts.snapperSubvolume = {
      text = ''
        if ! ${pkgs.btrfs-progs}/bin/btrfs subvolume show /.snapshots >/dev/null 2>&1; then
          ${pkgs.btrfs-progs}/bin/btrfs subvolume create /.snapshots
        fi
      '';
      deps = [];
    };

    # ---------- btrfs auto-scrub ----------
    services.btrfs.autoScrub = {
      enable = true;
      interval = "monthly";
      fileSystems = [ "/" ];
    };

    environment.systemPackages = with pkgs; [
      btrfs-assistant
      btrfs-progs
    ];
  };
}
