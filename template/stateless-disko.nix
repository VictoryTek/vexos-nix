# template/stateless-disko.nix
# Standalone disko disk layout for the VexOS stateless role.
# Used by scripts/stateless-setup.sh during initial installation from the NixOS ISO.
#
# This is NOT a NixOS module — it is a plain Nix file passed directly to the
# disko CLI.  The NixOS module equivalent is modules/stateless-disk.nix.
#
# Usage:
#   sudo nix run 'github:nix-community/disko/latest' -- \
#     --mode destroy,format,mount \
#     /tmp/vexos-stateless-disk.nix \
#     --arg disk '"/dev/nvme0n1"' \
#     --arg enableLuks 'false'
#
# Parameters:
#   disk       — block device path (string, e.g. "/dev/nvme0n1")
#   enableLuks — whether to use LUKS2 encryption (bool, default false)
#   luksName   — name of the LUKS device-mapper entry (string, default "cryptroot")
#   ...        — absorbs any extra arguments injected by disko (e.g. diskoFile, mode)
{ disk ? "/dev/nvme0n1", enableLuks ? false, luksName ? "cryptroot", ... }:
{
  disko.devices = {
    disk.main = {
      type   = "disk";
      device = disk;
      content = {
        type = "gpt";
        partitions =
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
          // (if enableLuks then {
            luks = {
              size     = "100%";
              priority = 2;
              content = {
                type  = "luks";
                name  = luksName;
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
          } else {
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
          });
      };
    };
  };
}
