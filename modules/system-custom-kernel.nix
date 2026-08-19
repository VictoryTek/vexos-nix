# modules/system-custom-kernel.nix
# Opt-in custom kernel track — selects a kernel from the pkgs/kernels/ registry
# instead of the role's default kernel.
#
# Enable via the standard feature toggle:
#   just enable-feature kernel && just rebuild
# (equivalent to /etc/nixos/features.nix: vexos.features.kernel.enable = true;)
#
# These kernels are NOT on cache.nixos.org — they are built by a host running
# modules/server/kernel-builder.nix and served over Harmonia. If that host has
# not built the currently-pinned version yet, Nix will silently fall back to
# compiling the kernel locally (hours, on this machine). `just update` and
# `just rebuild` guard against that by checking the cache first; see the
# _kernel-cache-guard recipe in the justfile.
#
# Priority note: boot.kernelPackages has several definitions across this repo,
# so this module slots deliberately into the existing ladder with
# lib.mkOverride 90 (lower number = higher priority):
#
#   1000  mkDefault      modules/system.nix
#    100  normal         modules/system-latest-kernel.nix, system-lts-kernel.nix
#     90  mkOverride     THIS MODULE — beats the role's default kernel track
#     75  mkOverride     modules/zfs-server.nix
#     50  mkForce        modules/gpu/vm-guest-additions.nix
#
# 90 outranks the role's normal kernel choice while still losing to the ZFS
# server pin and the VM guest-additions pin — VM variants keep their 6.12
# kernel even if this option is enabled.
{ config, pkgs, lib, ... }:
let
  cfg = config.vexos.features.kernel;
  available = lib.attrNames pkgs.vexos.kernels;
in
{
  options.vexos.features.kernel = {
    enable = lib.mkEnableOption "custom kernel from the pkgs/kernels registry";

    name = lib.mkOption {
      type = lib.types.enum available;
      default = "ogc";
      description = ''
        Which kernel from pkgs/kernels/ to use.

          ogc — Open Gaming Collective kernel. Unifies the patch sets of
                Bazzite, ChimeraOS, Nobara, PikaOS, Playtron and ASUS Linux
                into one upstream-first tree. Ships NTSYNC, sched_ext, and
                handheld/ASUS hardware enablement.

        The enum is generated from the registry, so adding a kernel there makes
        it selectable here automatically.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    boot.kernelPackages = lib.mkOverride 90
      (pkgs.linuxPackagesFor pkgs.vexos.kernels.${cfg.name});
  };
}
