# modules/system.nix
# General system-level configuration shared across all hosts (including VM).
# Includes btrfs snapshot management (snapper) and related GUI tools.
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

  # Create /.snapshots subvolume on first activation if root is btrfs.
  # Runs on every rebuild but is idempotent — snapper requires this subvolume
  # to exist before its services start, including on fresh VM installs.
  system.activationScripts.snapperSubvolume = {
    text = ''
      if ${pkgs.util-linux}/bin/findmnt -n -o FSTYPE / | grep -q '^btrfs$'; then
        if ! ${pkgs.btrfs-progs}/bin/btrfs subvolume show /.snapshots >/dev/null 2>&1; then
          ${pkgs.btrfs-progs}/bin/btrfs subvolume create /.snapshots
        fi
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
}
