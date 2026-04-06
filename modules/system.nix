# modules/system.nix
# General system-level configuration shared across physical hosts.
# Includes btrfs snapshot management (snapper) and related GUI tools.
#
# DO NOT import in hosts/vm.nix — VMs typically do not use btrfs.
{ pkgs, ... }:
{
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
}
