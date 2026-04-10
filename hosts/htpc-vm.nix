# hosts/htpc-vm.nix
# vexos — HTPC VM guest build (QEMU/KVM + VirtualBox).
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-htpc-vm
{ ... }:
{
  imports = [
    ../configuration-htpc.nix
    ../modules/gpu/vm.nix
  ];

  networking.hostName = "vexos-htpc-vm";

  system.nixos.distroName = "VexOS HTPC VM";
}
