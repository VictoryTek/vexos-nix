# modules/system-lts-kernel.nix
# Pins the kernel to Linux 6.12 LTS for roles that prioritise stability over
# bleeding-edge features (server, headless-server, htpc, stateless).
# Import this in configuration-*.nix files for those roles.
# Desktop roles use system-desktop-kernel.nix (currently 6.18, tracking Bazzite).
{ pkgs, ... }:
{
  boot.kernelPackages = pkgs.linuxPackages_6_12;
}
