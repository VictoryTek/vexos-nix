# modules/system-lts-kernel.nix
# Pins the kernel to Linux 6.12 LTS for roles that prioritise stability over
# bleeding-edge features (server, headless-server, htpc).
# Import this in configuration-*.nix files for those roles.
# Desktop and stateless roles use system-latest-kernel.nix (linuxPackages_latest).
{ pkgs, ... }:
{
  boot.kernelPackages = pkgs.linuxPackages_6_12;
}
