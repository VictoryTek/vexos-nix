# hosts/server-amd.nix
# vexos — Server AMD GPU build.
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-server-amd
{ lib, ... }:
{
  imports = [
    ../configuration-server.nix
    ../modules/gpu/amd.nix
  ];

  virtualisation.virtualbox.guest.enable = lib.mkForce false;
  system.nixos.distroName = "VexOS Server AMD";
}
