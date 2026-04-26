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

  system.nixos.distroName = "VexOS Stateless AMD";
}
