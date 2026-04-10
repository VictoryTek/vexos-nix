# modules/privacy-disk.nix
# Declarative disk layout for the VexOS privacy role using disko.
#
# Uses disko (github:nix-community/disko) to declare the full GPT partition
# table, LUKS2 container, and Btrfs subvolumes required by the privacy role.
#
# disko generates fileSystems."/nix", fileSystems."/persistent",
# fileSystems."/boot", and boot.initrd.luks.devices."cryptroot" automatically.
# This module replaces all hardware-UUID prerequisites previously documented
# in modules/impermanence.nix.
#
# IMPORTANT: hardware-configuration.nix MUST be generated with:
#   nixos-generate-config --no-filesystems --root /mnt
# to avoid fileSystems conflicts with disko's generated entries.
{ config, lib, inputs, ... }:

let
  cfg = config.vexos.privacy.disk;
in
{
  # Conditionally pull in the disko NixOS module.
  # Evaluated lazily: when cfg.enable = false (default) disko is never imported,
  # leaving non-privacy builds entirely unaffected.
  imports = lib.optionals cfg.enable [
    inputs.disko.nixosModules.disko
  ];

  options.vexos.privacy.disk = {

    enable = lib.mkOption {
      type        = lib.types.bool;
      default     = false;
      description = ''
        Enable disko-managed disk layout for the privacy role.
        When true, disko declares the full GPT + LUKS2 + Btrfs subvolume
        layout and generates fileSystems entries automatically.
        Requires a block device to be specified via vexos.privacy.disk.device.
      '';
    };

    device = lib.mkOption {
      type        = lib.types.str;
      default     = "/dev/nvme0n1";
      description = ''
        Block device to use for the privacy disk layout.
        This becomes disko.devices.disk.main.device.
        Examples: "/dev/nvme0n1"  "/dev/sda"  "/dev/vda"
        Override in your host file: vexos.privacy.disk.device = "/dev/sda";
      '';
    };

    enableLuks = lib.mkOption {
      type        = lib.types.bool;
      default     = true;
      description = ''
        Wrap the data partition in LUKS2 full-disk encryption.
        Set to false for VM guests that do not require disk encryption.
        When false, the Btrfs filesystem is created directly on the partition.
      '';
    };

    luksName = lib.mkOption {
      type        = lib.types.str;
      default     = "cryptroot";
      description = ''
        Name for the LUKS device-mapper entry.
        The decrypted device will appear at /dev/mapper/<luksName>.
      '';
    };

    memorySize = lib.mkOption {
      type        = lib.types.str;
      default     = "25%";
      description = ''
        Size passed to the tmpfs root mount (size= option).
        The tmpfs root is declared by modules/impermanence.nix, not here.
        This option is informational and may be used for documentation.
      '';
    };

  };

  config = lib.mkIf cfg.enable {

    disko.devices = {
      disk.main = {
        type   = "disk";
        device = cfg.device;
        content = {
          type = "gpt";
          partitions =
            # EFI System Partition — always present
            {
              ESP = {
                size     = "512MiB";
                type     = "EF00";
                priority = 1;
                content = {
                  type         = "filesystem";
                  format       = "vfat";
                  mountpoint   = "/boot";
                  mountOptions = [ "umask=0077" ];
                };
              };
            }
            # LUKS2-encrypted Btrfs (hardware installs)
            // lib.optionalAttrs cfg.enableLuks {
              luks = {
                size     = "100%";
                priority = 2;
                content = {
                  type  = "luks";
                  name  = cfg.luksName;
                  settings = {
                    allowDiscards    = true;
                    bypassWorkqueues = true;
                  };
                  content = {
                    type      = "btrfs";
                    extraArgs = [ "-f" ];
                    subvolumes = {
                      "@nix" = {
                        mountpoint   = "/nix";
                        mountOptions = [ "compress=zstd" "noatime" ];
                      };
                      "@persist" = {
                        mountpoint   = "/persistent";
                        mountOptions = [ "compress=zstd" "noatime" ];
                      };
                    };
                  };
                };
              };
            }
            # Plain Btrfs (VM installs — no LUKS overhead)
            // lib.optionalAttrs (!cfg.enableLuks) {
              data = {
                size     = "100%";
                priority = 2;
                content = {
                  type      = "btrfs";
                  extraArgs = [ "-f" ];
                  subvolumes = {
                    "@nix" = {
                      mountpoint   = "/nix";
                      mountOptions = [ "compress=zstd" "noatime" ];
                    };
                    "@persist" = {
                      mountpoint   = "/persistent";
                      mountOptions = [ "compress=zstd" "noatime" ];
                    };
                  };
                };
              };
            };
        };
      };
    };

    # disko generates fileSystems entries for /nix and /persistent but does
    # not set neededForBoot.  impermanence requires neededForBoot = true on
    # /persistent so that bind mounts are available during early userspace.
    # /nix is also flagged so the Nix store is available before activation.
    # lib.mkForce overrides the disko default (false) without causing a conflict.
    fileSystems."/persistent".neededForBoot = lib.mkForce true;
    fileSystems."/nix".neededForBoot        = lib.mkForce true;

  };
}
