# hosts/amd.nix
# vexos — AMD GPU desktop build.
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-desktop-amd
{ lib, ... }:
{
  imports = [
    ../configuration-desktop.nix
    ../modules/gpu/amd.nix
    ../modules/asus.nix
  ];

  system.nixos.distroName = "VexOS Desktop AMD";
}
