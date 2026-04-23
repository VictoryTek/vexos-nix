# hosts/headless-server-amd.nix
# vexos — Headless Server AMD GPU build.
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-headless-server-amd
{ lib, ... }:
{
  imports = [
    ../configuration-headless-server.nix
    ../modules/gpu/amd-headless.nix
  ];

  virtualisation.virtualbox.guest.enable = lib.mkForce false;
  system.nixos.distroName = "VexOS Headless Server AMD";
}
