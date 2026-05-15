# hosts/headless-server-vm.nix
# vexos — Headless Server VM guest build (QEMU/KVM + VirtualBox).
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-headless-server-vm
{ lib, ... }:
{
  imports = [
    ../configuration-headless-server.nix
    ../modules/gpu/vm.nix
  ];

  system.nixos.distroName = "VexOS Headless Server VM";

  # REQUIRED: replace with the real value from the target host.
  # Generate: head -c 8 /etc/machine-id
  networking.hostId = "b0000004";
}
