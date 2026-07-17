# modules/server/mergerfs.nix
# mergerfs union pool — the "bulk NAS" storage tier.
#
# mergerfs is a FUSE union filesystem: it presents N independently-formatted
# disks (each with its own ext4/XFS) as one directory tree at `mountPoint`.
# It does NO striping and NO redundancy itself — pooling only. Redundancy for
# this tier is provided out-of-band by SnapRAID (see modules/server/snapraid.nix).
#
# Why this tier exists (vs. the ZFS pool in modules/zfs-server.nix):
#   ZFS cannot gracefully pool mismatched drives added one at a time (raidz caps
#   at the smallest disk per vdev; mirrors need matched pairs). mergerfs pools
#   ANY size/model disk, added individually with zero rebalance, and each disk
#   stays independently readable on any Linux box. This is the right tier for
#   large, write-once media libraries and general bulk storage — NOT for
#   databases or Proxmox zvols (those stay on ZFS).
#
# Persistence: branch mounts and the union mount are declared here from the
# `branches` option, because NixOS generates /etc/fstab (a hand-edited fstab
# would not survive a rebuild). The option values themselves are written to
# /etc/nixos/storage-pool.nix by `just create-mergerfs-pool`.
#
# Per the Option B module pattern: this file only declares options + their
# config, gated by the module's own `enable` (the standard toggleable-subsystem
# carve-out). It is imported unconditionally via modules/server/default.nix and
# stays inert until vexos.server.storage.mergerfs.enable = true.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.storage.mergerfs;

  branchModule = lib.types.submodule {
    options = {
      mountPoint = lib.mkOption {
        type = lib.types.str;
        example = "/mnt/disk1";
        description = "Local mountpoint for this content disk (a mergerfs branch).";
      };
      device = lib.mkOption {
        type = lib.types.str;
        example = "/dev/disk/by-uuid/1111-2222";
        description = "Block device for this branch, by-uuid or by-id (stable across renames).";
      };
      fsType = lib.mkOption {
        type = lib.types.str;
        default = "ext4";
        example = "xfs";
        description = "Filesystem on the branch disk (ext4 or xfs).";
      };
    };
  };

  # Colon-separated branch list is mergerfs' native device syntax.
  branchDevices = lib.concatMapStringsSep ":" (b: b.mountPoint) cfg.branches;

  # Ensure the union unit is ordered after every branch mount.
  branchRequiresOpts = map (b: "x-systemd.requires-mounts-for=${b.mountPoint}") cfg.branches;

  # Per-branch fileSystems entries (the underlying content disks).
  branchFileSystems = builtins.listToAttrs (map (b: {
    name = b.mountPoint;
    value = {
      device = b.device;
      fsType = b.fsType;
      # nofail: a single failed branch must not drop the host to emergency mode —
      # mergerfs simply starts with the surviving branches, and SnapRAID handles
      # recovery of the failed disk.
      options = [ "defaults" "nofail" ];
    };
  }) cfg.branches);
in
{
  options.vexos.server.storage.mergerfs = {
    enable = lib.mkEnableOption "mergerfs union pool for bulk/media NAS storage";

    mountPoint = lib.mkOption {
      type = lib.types.str;
      default = "/storage";
      description = "Mountpoint of the unified mergerfs pool. Samba/NFS shares point here.";
    };

    branches = lib.mkOption {
      type = lib.types.listOf branchModule;
      default = [ ];
      description = ''
        Content disks unioned into the pool. Populated by
        `just create-mergerfs-pool` into /etc/nixos/storage-pool.nix.
      '';
    };

    options = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "cache.files=partial"
        "dropcacheonclose=true"
        "category.create=mfs"   # create new files on the branch with most free space
        "moveonenospc=true"     # transparently retry a write on another branch if one fills
        "minfreespace=20G"
        "fsname=mergerfs"
        "allow_other"           # let Samba/NFS/services (other UIDs) read the pool
        "use_ino"
      ];
      description = "mergerfs mount options (excluding the auto-added ordering options).";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.branches != [ ];
        message = ''
          vexos.server.storage.mergerfs.enable = true but no branches are defined.
          Run `just create-mergerfs-pool` to build the pool and populate
          /etc/nixos/storage-pool.nix.
        '';
      }
    ];

    environment.systemPackages = [ pkgs.mergerfs ];

    # allow_other requires user_allow_other in /etc/fuse.conf.
    programs.fuse.userAllowOther = true;

    fileSystems = branchFileSystems // {
      "${cfg.mountPoint}" = {
        device = branchDevices;
        fsType = "fuse.mergerfs";
        options = cfg.options ++ branchRequiresOpts;
      };
    };
  };
}
