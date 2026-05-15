# hosts/server-nvidia.nix
# vexos — Server NVIDIA GPU build.
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-server-nvidia
{ lib, ... }:
{
  imports = [
    ../configuration-server.nix
    ../modules/gpu/nvidia.nix
  ];

  system.nixos.distroName = "VexOS Server NVIDIA";

  # REQUIRED: replace with the real value from the target host.
  # Generate: head -c 8 /etc/machine-id
  networking.hostId = "a0000002";
}
