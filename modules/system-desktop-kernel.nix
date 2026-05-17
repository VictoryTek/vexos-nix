# modules/system-desktop-kernel.nix
# Desktop kernel track — targets the highest kernel that works with the current
# NVIDIA stable driver in nixpkgs.
#
# Current hold: Linux 6.18 — NVIDIA 580.142 fails on Linux 7.x (unknown pseudo-op .ryte).
# Upgrade path: bump to linuxPackages_latest (or OGC kernel via binary cache) once
# NVIDIA 595.x (or a patched 580.x) lands in nixpkgs and validates against Linux 7.x.
#
# Bazzite reference: kernel 6.19.14-ogc + NVIDIA 595.71.05 (as of 2026-05-15)
{ pkgs, ... }:
{
  boot.kernelPackages = pkgs.linuxPackages_6_18;
}
