# hosts/amd.nix
# vexos — AMD GPU system build.
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-amd
{ ... }:
{
  imports = [
    ../configuration.nix
    ../modules/gpu/amd.nix
    ../modules/asus.nix
  ];

  # Hostname matches the flake output name so nixos-rebuild can auto-detect
  # this config without requiring an explicit #target argument.
  networking.hostName = "vexos-amd";
}
