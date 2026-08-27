# hosts/vanilla-vm.nix
# vexos — Vanilla VM guest build (stock NixOS baseline).
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-vanilla-vm
#
# Guest additions come from ../modules/gpu/vanilla-vm.nix, matching how every
# other hosts/*-vm.nix imports its GPU module. This file previously inlined a
# partial copy of those settings instead — which meant the in-repo
# vexos-vanilla-vm output never used modules/gpu/vanilla-vm.nix at all (that
# module reached only the /etc/nixos template consumers, via flake.nix's
# nixosModules.gpuVanillaVm export), and pinned
# virtualisation.virtualbox.guest.enable = true regardless of vexos.vm.platform.
{ ... }:
{
  imports = [
    ../configuration-vanilla.nix
    ../modules/gpu/vanilla-vm.nix
  ];

  system.nixos.distroName = "VexOS Vanilla VM";
}
