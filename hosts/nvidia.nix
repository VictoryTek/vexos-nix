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

  # Hostname matches the flake output name so nixos-rebuild can auto-detect
  # this config without requiring an explicit #target argument.
  networking.hostName = "vexos-nvidia";
}
