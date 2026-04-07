# hosts/nvidia.nix
# vexos — NVIDIA GPU desktop build.
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-desktop-nvidia
{ ... }:
{
  imports = [
    ../configuration.nix
    ../modules/gpu/nvidia.nix
    ../modules/asus.nix
    ../modules/system.nix
  ];
}
