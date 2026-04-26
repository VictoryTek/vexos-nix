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

  system.nixos.distroName = "VexOS Stateless Intel";
}
