# hosts/vm.nix
# vexos — Virtual machine guest build (QEMU/KVM + VirtualBox).
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-vm
#
# Bazzite kernel: applied here for testing purposes only.
# lib.mkOverride 49 is required to override both:
#   - modules/performance.nix (normal priority, CachyOS kernel)
#   - modules/gpu/vm.nix (lib.mkForce / priority 50, LTS kernel)
# Priority 49 < 50, so this definition wins cleanly without a conflict.
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
{ pkgs, lib, inputs, ... }:
{
  imports = [
    ../configuration.nix
    ../modules/gpu/vm.nix
  ];

  # Bazzite kernel — overrides modules/gpu/vm.nix LTS (lib.mkForce/priority 50) and
  # modules/performance.nix CachyOS setting (normal priority).
  # mkOverride 49 wins over modules/gpu/vm.nix which uses mkForce (priority 50).
  #
  # References inputs.kernel-bazzite.packages directly so the store path matches
  # exactly what Garnix CI built and cached from the vex-kernels repo.  Re-deriving
  # via pkgs.callPackage would use vexos-nix's nixos-25.11 pkgs instead of
  # vex-kernels' nixos-unstable pkgs, producing a different store path and a
  # guaranteed cache miss on every rebuild.
  boot.kernelPackages = lib.mkOverride 49 (
    pkgs.linuxPackagesFor inputs.kernel-bazzite.packages.x86_64-linux.linux-bazzite
  );

  # Distinguish the VM host on the network
  networking.hostName = "vexos-vm";
}
