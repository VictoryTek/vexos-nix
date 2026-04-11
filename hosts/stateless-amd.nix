# hosts/stateless-amd.nix
# vexos — Stateless AMD GPU build (no gaming, development, virtualization, or ASUS modules).
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-stateless-amd
{ lib, ... }:
{
  imports = [
    ../configuration-stateless.nix
    ../modules/gpu/amd.nix
    ../modules/stateless-disk.nix
  ];

  # Override with the actual disk device on the target machine.
  # Default "/dev/nvme0n1" is suitable for most modern AMD laptops/desktops.
  # Check with: lsblk -d -o NAME,SIZE,MODEL
  vexos.stateless.disk = {
    enable = true;
    device = lib.mkDefault "/dev/nvme0n1";
  };

  # Prevent hardware-configuration.nix (generated on a VM) from accidentally
  # enabling VirtualBox guest additions on a bare-metal host. Guest additions
  # fail to build against linuxPackages_latest (kernel 6.12+).
  virtualisation.virtualbox.guest.enable = lib.mkForce false;
  system.nixos.distroName = "VexOS Stateless AMD";
}
