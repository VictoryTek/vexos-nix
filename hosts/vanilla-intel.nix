# hosts/vanilla-intel.nix
# vexos — Vanilla Intel build (stock NixOS baseline).
# GPU uses kernel i915 driver (auto-loaded). No custom GPU configuration.
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-vanilla-intel
{ lib, ... }:
{
  imports = [
    ../configuration-vanilla.nix
  ];

  system.nixos.distroName = "VexOS Vanilla Intel";
}
