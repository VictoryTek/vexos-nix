# hosts/nvidia.nix
# vexos — NVIDIA GPU desktop build.
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-desktop-nvidia
{ lib, ... }:
{
  imports = [
    ../configuration-desktop.nix
    ../modules/gpu/nvidia.nix
  ];

  vexos.hardware.asus.enable = true;
  system.nixos.distroName = "VexOS Desktop NVIDIA";
}
