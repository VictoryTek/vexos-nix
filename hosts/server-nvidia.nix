# hosts/server-nvidia.nix
# vexos — Server NVIDIA GPU build.
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-server-nvidia
{ lib, ... }:
{
  imports = [
    ../configuration-server.nix
    ../modules/gpu/nvidia.nix
  ];

  virtualisation.virtualbox.guest.enable = lib.mkForce false;
  system.nixos.distroName = "VexOS Server NVIDIA";
}
