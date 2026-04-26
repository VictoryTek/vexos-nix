# hosts/htpc-amd.nix
# vexos — HTPC AMD GPU build.
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-htpc-amd
{ lib, ... }:
{
  imports = [
    ../configuration-htpc.nix
    ../modules/gpu/amd.nix
  ];

  system.nixos.distroName = "VexOS HTPC AMD";
}
