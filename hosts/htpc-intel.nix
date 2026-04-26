# hosts/htpc-intel.nix
# vexos — HTPC Intel GPU build (integrated iGPU or Arc A-series discrete).
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-htpc-intel
{ lib, ... }:
{
  imports = [
    ../configuration-htpc.nix
    ../modules/gpu/intel.nix
  ];

  system.nixos.distroName = "VexOS HTPC Intel";
}
