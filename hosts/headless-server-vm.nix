# hosts/headless-server-vm.nix
# vexos — Headless Server VM guest build (QEMU/KVM + VirtualBox).
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-headless-server-vm
{ lib, ... }:
{
  imports = [
    ../configuration-headless-server.nix
    ../modules/gpu/vm.nix
  ];

  networking.hostName = lib.mkDefault "vexos";

  system.nixos.distroName = "VexOS Headless Server VM";
}
