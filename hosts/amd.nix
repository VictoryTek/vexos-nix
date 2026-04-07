# hosts/amd.nix
# vexos — AMD GPU desktop build.
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-desktop-amd
{ ... }:
{
  imports = [
    ../configuration.nix
    ../modules/gpu/amd.nix
    ../modules/asus.nix
  ];
}
