# hosts/amd.nix
# vexos — AMD GPU desktop build.
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-desktop-amd
{ lib, ... }:
{
  imports = [
    ../configuration-desktop.nix
    ../modules/gpu/amd.nix
  ];

  vexos.hardware.asus.enable = true;
  vexos.hardware.asus.batteryChargeLimit = 80;
  system.nixos.distroName = "VexOS Desktop AMD";
}
