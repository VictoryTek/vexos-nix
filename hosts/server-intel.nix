# hosts/server-intel.nix
# vexos — Server Intel GPU build (integrated iGPU or Arc A-series discrete).
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-server-intel
{ lib, ... }:
{
  imports = [
    ../configuration-server.nix
    ../modules/gpu/intel.nix
  ];

  system.nixos.distroName = "VexOS Server Intel";
}
