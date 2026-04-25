# hosts/htpc-intel.nix
# vexos — HTPC Intel GPU build (integrated iGPU or Arc A-series discrete).
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-htpc-intel
{ lib, ... }:
{
  imports = [
    ../configuration-htpc.nix
    ../modules/gpu/intel.nix
  ];

  environment.etc."nixos/vexos-variant".text = "vexos-htpc-intel\n";
  virtualisation.virtualbox.guest.enable = lib.mkForce false;
  system.nixos.distroName = "VexOS HTPC Intel";
}
