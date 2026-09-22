# template/disko-layout.nix
# Standalone disko disk layout for a fresh VexOS bare-metal install, any role.
# Used by scripts/bare-metal-install.sh during initial installation from the
# NixOS live ISO.
#
# This is NOT a NixOS module — it is a plain Nix file passed directly to the
# disko CLI. The NixOS module equivalent for the stateless role's own
# @nix/@persist subvolume layout is modules/stateless-disk.nix; the
# conventional (non-stateless) layout needs no equivalent module — those
# roles get their fileSystems straight from a freshly generated
# hardware-configuration.nix instead (see bare-metal-install.sh).
#
# Usage:
#   sudo nix run 'github:nix-community/disko/latest' -- \
#     --mode destroy,format,mount \
#     /tmp/vexos-disko-layout.nix \
#     --arg disk '"/dev/nvme0n1"' \
#     --arg enableLuks 'false' \
#     --arg stateless 'true'
#
# Parameters:
#   disk       — block device path (string, e.g. "/dev/nvme0n1")
#   enableLuks — whether to use LUKS2 encryption (bool, default false)
#   luksName   — name of the LUKS device-mapper entry (string, default "cryptroot")
#   stateless  — true (default): Btrfs root with @nix (→/nix) and @persist
#                (→/persistent) subvolumes, for the impermanence-based
#                stateless role.
#                false: a single conventional Btrfs partition mounted
#                directly at "/", for every other role. No subvolume split —
#                those roles have no impermanence needs.
#   ...        — absorbs any extra arguments injected by disko (e.g. diskoFile, mode)
{ disk ? "/dev/nvme0n1", enableLuks ? false, luksName ? "cryptroot", stateless ? true, ... }:
let
  # The one real difference between the two layouts — everything else
  # (ESP, LUKS wrapping, "100%" sizing) is identical either way.
  rootContent =
    if stateless then {
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
    } else {
      type         = "btrfs";
      extraArgs    = [ "-f" ];
      mountpoint   = "/";
      mountOptions = [ "compress=zstd" "noatime" ];
    };
in
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
              size     = "512M";
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
                content = rootContent;
              };
            };
          } else {
            data = {
              size     = "100%";
              priority = 2;
              content  = rootContent;
            };
          });
      };
    };
  };
}
