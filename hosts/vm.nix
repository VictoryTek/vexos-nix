# hosts/vm.nix
# vexos — Virtual machine guest build (QEMU/KVM + VirtualBox).
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-vm
#
# Bootloader: NOT configured here — set it in your host's hardware-configuration.nix.
# configuration.nix uses lib.mkDefault for bootloader, so hardware-configuration.nix wins.
#
# BIOS VM example (add to /etc/nixos/hardware-configuration.nix):
#   boot.loader.systemd-boot.enable = false;
#   boot.loader.grub = { enable = true; device = "/dev/sda"; efiSupport = false; };
#
# UEFI VM example (add to /etc/nixos/hardware-configuration.nix):
#   boot.loader.systemd-boot.enable = false;
#   boot.loader.grub = { enable = true; device = "nodev"; efiSupport = true;
#                        efiInstallAsRemovable = true; };
{ ... }:
{
  imports = [
    ../configuration.nix
    ../modules/gpu/vm.nix
  ];

  # Distinguish the VM host on the network
  networking.hostName = "vexos-vm";
}
