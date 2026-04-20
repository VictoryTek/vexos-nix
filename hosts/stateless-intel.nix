# hosts/stateless-intel.nix
# vexos — Stateless Intel GPU build (no gaming, development, virtualization, or ASUS modules).
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-stateless-intel
{ lib, ... }:
{
  imports = [
    ../configuration-stateless.nix
    ../modules/gpu/intel.nix
    ../modules/stateless-disk.nix
  ];

  # Override with the actual disk device on the target machine.
  # Check with: lsblk -d -o NAME,SIZE,MODEL
  vexos.stateless.disk = {
    enable = true;
    device = lib.mkDefault "/dev/nvme0n1";
  };

  # Prevent hardware-configuration.nix (generated on a VM) from accidentally
  # enabling VirtualBox guest additions on a bare-metal host. Guest additions
  # fail to build against linuxPackages_latest (kernel 6.12+).
  virtualisation.virtualbox.guest.enable = lib.mkForce false;
  system.nixos.distroName = "VexOS Stateless Intel";
  vexos.variant = "vexos-stateless-intel";
}
