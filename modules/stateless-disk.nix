# modules/stateless-disk.nix
# Filesystem declarations for the VexOS stateless role.
#
# This module declares the expected filesystem mounts for the stateless role
# using lib.mkDefault (lowest priority), so that hardware-configuration.nix
# can override these entries with UUID-based device paths when rebuilding from
# an existing system.
#
# Workflow — two supported paths:
#
#   Fresh install from ISO:
#     1. Run scripts/stateless-setup.sh from the NixOS live ISO
#     2. disko CLI formats the disk (creates ESP + Btrfs @nix/@persist subvols)
#     3. nixos-install is called; this module provides fileSystems fallbacks
#        when hardware-configuration.nix is generated with --no-filesystems
#
#   Rebuild from existing system (preferred):
#     1. Run scripts/migrate-to-stateless.sh on the running NixOS system
#     2. The migration script creates Btrfs subvols and regenerates
#        hardware-configuration.nix with exact UUID-based filesystem entries
#     3. Those hardware-configuration.nix entries override this module's
#        mkDefault declarations (higher priority wins — no conflicts)
#     4. Run: sudo nixos-rebuild switch --flake /etc/nixos#vexos-stateless-<variant>
#
# No LUKS. Disk layout: FAT32 /boot (EFI) + plain Btrfs root partition
# with @nix (→/nix) and @persist (→/persistent) subvolumes.
{ config, lib, ... }:

let
  cfg = config.vexos.stateless.disk;
in
{
  options.vexos.stateless.disk = {

    enable = lib.mkOption {
      type        = lib.types.bool;
      default     = false;
      description = ''
        Enable filesystem declarations for the stateless role.
        When true, this module declares lib.mkDefault fileSystems for /boot,
        /nix, and /persistent based on the disk device path.
        hardware-configuration.nix UUID-based declarations take priority and
        override these defaults automatically when present.
      '';
    };

    device = lib.mkOption {
      type        = lib.types.str;
      default     = "/dev/nvme0n1";
      description = ''
        Full disk device path (not a partition).
        Partition paths are derived automatically:
          nvme/mmcblk: <device>p1 (boot) and <device>p2 (root)
          sata/virtio: <device>1  (boot) and <device>2  (root)
        Examples: "/dev/nvme0n1"  "/dev/sda"  "/dev/vda"
        This default is overridden by hardware-configuration.nix UUID paths
        when scripts/migrate-to-stateless.sh has been run.
      '';
    };

  };

  config = lib.mkIf cfg.enable (
    let
      # Derive partition paths from the disk device.
      # nvme and mmcblk use "p" separator before partition number.
      isNvmeStyle = builtins.match ".*(nvme|mmcblk).*" cfg.device != null;
      bootPart    = if isNvmeStyle then "${cfg.device}p1" else "${cfg.device}1";
      rootPart    = if isNvmeStyle then "${cfg.device}p2" else "${cfg.device}2";
    in
    {
      # Force unconditional early loading of btrfs — availableKernelModules relies
      # on udev hotplug ordering which is unreliable in early initrd.
      boot.initrd.kernelModules = lib.mkDefault [ "btrfs" ];

      # ── Boot partition (EFI / FAT32) ──────────────────────────────────────
      # lib.mkDefault: hardware-configuration.nix overrides with UUID path.
      fileSystems."/boot" = lib.mkDefault {
        device  = bootPart;
        fsType  = "vfat";
        options = [ "fmask=0077" "dmask=0077" ];
      };

      # ── Nix store (persistent) ────────────────────────────────────────────
      # Mounted from the @nix Btrfs subvolume on the root partition.
      # neededForBoot = true: must be available before activation scripts run.
      fileSystems."/nix" = lib.mkDefault {
        device        = rootPart;
        fsType        = "btrfs";
        options       = [ "subvol=@nix" "compress=zstd" "noatime" ];
        neededForBoot = lib.mkForce true;
      };

      # ── Persistent state ──────────────────────────────────────────────────
      # Mounted from the @persist Btrfs subvolume on the root partition.
      # neededForBoot = true: required by impermanence bind mounts.
      fileSystems."/persistent" = lib.mkDefault {
        device        = rootPart;
        fsType        = "btrfs";
        options       = [ "subvol=@persist" "compress=zstd" "noatime" ];
        neededForBoot = true;
      };
    }
  );
}
