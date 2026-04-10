# hosts/htpc-vm.nix
# vexos — HTPC VM guest build (QEMU/KVM + VirtualBox).
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-htpc-vm
{ inputs, ... }:
{
  imports = [
    ../configuration-htpc.nix
    ../modules/gpu/vm.nix
  ];

  networking.hostName = "vexos-htpc-vm";

  environment.systemPackages = [
    inputs.up.packages.x86_64-linux.default
  ];
  system.nixos.distroName = "VexOS HTPC VM";
}
