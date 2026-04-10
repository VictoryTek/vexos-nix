# hosts/privacy-vm.nix
# vexos — Privacy VM guest build (no gaming, development, virtualization, or ASUS modules).
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-privacy-vm
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
    ../configuration-privacy.nix
    ../modules/gpu/vm.nix
  ];

  networking.hostName = "vexos-privacy-vm";

  environment.systemPackages = [
    inputs.up.packages.x86_64-linux.default
  ];
  system.nixos.distroName = "VexOS Privacy VM";
}
