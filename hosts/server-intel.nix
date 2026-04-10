# hosts/server-intel.nix
# vexos — Server Intel GPU build (integrated iGPU or Arc A-series discrete).
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-server-intel
{ lib, ... }:
{
  imports = [
    ../configuration-server.nix
    ../modules/gpu/intel.nix
  ];

  virtualisation.virtualbox.guest.enable = lib.mkForce false;
  system.nixos.distroName = "VexOS Server Intel";
}
