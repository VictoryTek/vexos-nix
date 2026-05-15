# hosts/vanilla-nvidia.nix
# vexos — Vanilla NVIDIA build (stock NixOS baseline).
# GPU uses kernel nouveau driver (open-source). No proprietary NVIDIA drivers.
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-vanilla-nvidia
{ lib, ... }:
{
  imports = [
    ../configuration-vanilla.nix
  ];

  system.nixos.distroName = "VexOS Vanilla NVIDIA";
}
