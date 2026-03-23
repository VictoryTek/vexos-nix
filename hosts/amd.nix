# hosts/amd.nix
# vexos — AMD GPU system build.
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-amd
{ ... }:
{
  imports = [
    ../configuration.nix
    ../modules/gpu/amd.nix
  ];
}
