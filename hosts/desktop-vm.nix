# hosts/vm.nix
# vexos — Virtual machine guest desktop build (QEMU/KVM + VirtualBox).
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-desktop-vm
#
# Bootloader: NOT configured here — set it in your host's hardware-configuration.nix.
#
# BIOS VM example (add to /etc/nixos/hardware-configuration.nix):
#   boot.loader.systemd-boot.enable = false;
#   boot.loader.grub = { enable = true; device = "/dev/sda"; efiSupport = false; };
#
# UEFI VM example (add to /etc/nixos/hardware-configuration.nix):
#   boot.loader.systemd-boot.enable = false;
#   boot.loader.grub = { enable = true; device = "nodev"; efiSupport = true;
#                        efiInstallAsRemovable = true; };
{ lib, ... }:
{
  imports = [
    ../configuration-desktop.nix
    ../modules/gpu/vm.nix
  ];

  # vexos.btrfs.enable = false and vexos.swap.enable = false are set in
  # modules/gpu/vm.nix so they apply to both repo builds and the external
  # /etc/nixos/flake.nix template that consumes nixosModules.gpuVm.

  # vexos.hardware.asus.enable = false; # VM — no physical ASUS hardware
  system.nixos.distroName = "VexOS Desktop VM";
}
