# hosts/stateless-nvidia.nix
# vexos — Stateless NVIDIA GPU build (no gaming, development, virtualization, or ASUS modules).
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-stateless-nvidia
{ lib, ... }:
{
  imports = [
    ../configuration-stateless.nix
    ../modules/gpu/nvidia.nix
    ../modules/stateless-disk.nix
  ];

  # Override with the actual disk device on the target machine.
  # Check with: lsblk -d -o NAME,SIZE,MODEL
  vexos.stateless.disk = {
    enable = true;
    device = lib.mkDefault "/dev/nvme0n1";
  };

  system.nixos.distroName = "VexOS Stateless NVIDIA";
}
