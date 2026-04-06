# hosts/intel.nix
# vexos — Intel GPU system build (integrated iGPU or Arc A-series discrete).
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-intel
{ ... }:
{
  imports = [
    ../configuration.nix
    ../modules/gpu/intel.nix
    ../modules/system.nix
  ];
}
