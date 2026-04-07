# hosts/intel.nix
# vexos — Intel GPU desktop build (integrated iGPU or Arc A-series discrete).
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-desktop-intel
{ ... }:
{
  imports = [
    ../configuration.nix
    ../modules/gpu/intel.nix
  ];
}
