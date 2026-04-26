# hosts/headless-server-nvidia.nix
# vexos — Headless Server NVIDIA GPU build.
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-headless-server-nvidia
{ lib, ... }:
{
  imports = [
    ../configuration-headless-server.nix
    ../modules/gpu/nvidia-headless.nix
  ];

  system.nixos.distroName = "VexOS Headless Server NVIDIA";
}
