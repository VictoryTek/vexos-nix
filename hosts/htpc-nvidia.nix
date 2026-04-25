# hosts/htpc-nvidia.nix
# vexos — HTPC NVIDIA GPU build.
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-htpc-nvidia
{ lib, ... }:
{
  imports = [
    ../configuration-htpc.nix
    ../modules/gpu/nvidia.nix
  ];

  environment.etc."nixos/vexos-variant".text = "vexos-htpc-nvidia\n";
  virtualisation.virtualbox.guest.enable = lib.mkForce false;
  system.nixos.distroName = "VexOS HTPC NVIDIA";
}
