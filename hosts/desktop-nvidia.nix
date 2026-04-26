# hosts/nvidia.nix
# vexos — NVIDIA GPU desktop build.
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-desktop-nvidia
{ lib, ... }:
{
  imports = [
    ../configuration-desktop.nix
    ../modules/gpu/nvidia.nix
    ../modules/asus.nix
  ];

  system.nixos.distroName = "VexOS Desktop NVIDIA";
}
