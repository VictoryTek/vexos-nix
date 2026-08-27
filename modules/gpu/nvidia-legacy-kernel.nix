# modules/gpu/nvidia-legacy-kernel.nix
# Kernel pin for the legacy_580 NVIDIA variant on latest-kernel roles.
#
# NVIDIA 580.173.02 (the last branch supporting Maxwell/Pascal/Volta) does not
# build against Linux 7.2 — its os-interface.c still calls strncpy(), which 7.2
# removed from the kernel-space string API. It builds cleanly on 7.1 and 6.12
# (both verified), so hosts on this variant are held at 7.1.
#
# 7.1 is current mainline, one minor release behind latest — NOT an LTS or
# maintenance kernel. The desktop and stateless roles keep linuxPackages_latest
# (7.2) for every other GPU, including the "latest" NVIDIA variant, which builds
# on 7.2 via the CachyOS compat patch in modules/gpu/nvidia.nix.
#
# Imported only by flake.nix's mkHost, and only for roles whose default kernel
# track is linuxPackages_latest (desktop, stateless). Roles on the LTS track
# (server, headless-server, htpc) already sit at 6.12, where 580 builds fine,
# so they must NOT import this — it would move them off LTS.
#
# Priority note: boot.kernelPackages has several definitions across this repo.
# This module slots into the existing ladder at lib.mkOverride 95 (lower number
# = higher priority):
#
#   1000  mkDefault      modules/system.nix
#    100  normal         modules/system-latest-kernel.nix, system-lts-kernel.nix
#     95  mkOverride     THIS MODULE — beats the role's default kernel track
#     90  mkOverride     modules/system-custom-kernel.nix
#     75  mkOverride     modules/zfs-server.nix
#     50  mkForce        modules/gpu/vm-guest-additions.nix
#
# 95 outranks the role's normal kernel choice while still losing to the opt-in
# custom kernel (`just enable-feature kernel`), the ZFS server pin and the VM
# guest-additions pin.
#
# REMOVE THIS once nixpkgs ships a 580.x build that works on 7.2 — or drop it
# together with the legacy_580 variant if that hardware is retired.
{ pkgs, lib, ... }:
{
  boot.kernelPackages = lib.mkOverride 95 pkgs.linuxPackages_7_1;
}
