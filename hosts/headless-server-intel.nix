# hosts/headless-server-intel.nix
# vexos — Headless Server Intel GPU build (integrated iGPU or Arc A-series discrete).
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-headless-server-intel
{ lib, ... }:
{
  imports = [
    ../configuration-headless-server.nix
    ../modules/gpu/intel-headless.nix
  ];

  system.nixos.distroName = "VexOS Headless Server Intel";

  # REQUIRED: replace with the real value from the target host.
  # Generate: head -c 8 /etc/machine-id
  networking.hostId = "b0000003";
}
