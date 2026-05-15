# hosts/headless-server-amd.nix
# vexos — Headless Server AMD GPU build.
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-headless-server-amd
{ lib, ... }:
{
  imports = [
    ../configuration-headless-server.nix
    ../modules/gpu/amd-headless.nix
  ];

  system.nixos.distroName = "VexOS Headless Server AMD";

  # REQUIRED: replace with the real value from the target host.
  # Generate: head -c 8 /etc/machine-id
  networking.hostId = "b0000001";
}
