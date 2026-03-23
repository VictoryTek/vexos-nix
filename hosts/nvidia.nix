# hosts/nvidia.nix
# vexos — NVIDIA GPU system build.
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-nvidia
{ ... }:
{
  imports = [
    ../configuration.nix
    ../modules/gpu/nvidia.nix
    ../modules/asus.nix
  ];
}
