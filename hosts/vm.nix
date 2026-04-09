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
{ inputs, ... }:
{
  imports = [
    ../configuration.nix
    ../modules/gpu/vm.nix
  ];

  networking.hostName = "vexos-desktop-vm";

  # VMs rely on hypervisor memory management — no disk swap file needed.
  vexos.swap.enable = false;
  # VM btrfs layout is not snapper-compatible — disable btrfs/snapper integration.
  vexos.btrfs.enable = false;

  environment.systemPackages = [
    inputs.up.packages.x86_64-linux.default
  ];
  system.nixos.distroName = "VexOS Desktop VM";
}
