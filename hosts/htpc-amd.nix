# hosts/htpc-amd.nix
# vexos — HTPC AMD GPU build.
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-htpc-amd
{ lib, ... }:
{
  imports = [
    ../configuration-htpc.nix
    ../modules/gpu/amd.nix
  ];

  environment.etc."nixos/vexos-variant".text = "vexos-htpc-amd\n";
  virtualisation.virtualbox.guest.enable = lib.mkForce false;
  system.nixos.distroName = "VexOS HTPC AMD";
}
