# hosts/server-amd.nix
# vexos — Server AMD GPU build.
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-server-amd
{ lib, ... }:
{
  imports = [
    ../configuration-server.nix
    ../modules/gpu/amd.nix
  ];

  system.nixos.distroName = "VexOS Server AMD";

  # REQUIRED: replace with the real value from the target host.
  # Generate: head -c 8 /etc/machine-id
  networking.hostId = "a0000001";
}
