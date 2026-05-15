# hosts/intel.nix
# vexos — Intel GPU desktop build (integrated iGPU or Arc A-series discrete).
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-desktop-intel
{ lib, ... }:
{
  imports = [
    ../configuration-desktop.nix
    ../modules/gpu/intel.nix
  ];

  vexos.hardware.asus.enable = true;
  system.nixos.distroName = "VexOS Desktop Intel";
}
