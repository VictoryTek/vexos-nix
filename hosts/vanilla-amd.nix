# hosts/vanilla-amd.nix
# vexos — Vanilla AMD build (stock NixOS baseline).
# GPU uses kernel amdgpu driver (auto-loaded). No custom GPU configuration.
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-vanilla-amd
{ lib, ... }:
{
  imports = [
    ../configuration-vanilla.nix
  ];

  system.nixos.distroName = "VexOS Vanilla AMD";
}
