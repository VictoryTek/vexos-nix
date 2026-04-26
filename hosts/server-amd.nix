# hosts/server-amd.nix
# vexos — Server AMD GPU build.
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-server-amd
{ lib, ... }:
{
  imports = [
    ../configuration-server.nix
    ../modules/gpu/amd.nix
  ];

  system.nixos.distroName = "VexOS Server AMD";
}
