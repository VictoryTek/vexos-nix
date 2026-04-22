# hosts/headless-server-intel.nix
# vexos — Headless Server Intel GPU build (integrated iGPU or Arc A-series discrete).
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-headless-server-intel
{ lib, ... }:
{
  imports = [
    ../configuration-headless-server.nix
    ../modules/gpu/intel.nix
  ];

  virtualisation.virtualbox.guest.enable = lib.mkForce false;
  system.nixos.distroName = "VexOS Headless Server Intel";
}
