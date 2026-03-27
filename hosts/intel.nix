# hosts/intel.nix
# vexos — Intel GPU system build (integrated iGPU or Arc A-series discrete).
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-intel
{ ... }:
{
  imports = [
    ../configuration.nix
    ../modules/gpu/intel.nix
  ];

  # Hostname matches the flake output name so nixos-rebuild can auto-detect
  # this config without requiring an explicit #target argument.
  networking.hostName = "vexos-intel";
}
