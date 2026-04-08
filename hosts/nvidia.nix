# hosts/nvidia.nix
# vexos — NVIDIA GPU desktop build.
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-desktop-nvidia
{ lib, ... }:
{
  imports = [
    ../configuration.nix
    ../modules/gpu/nvidia.nix
    ../modules/asus.nix
  ];

  # Prevent hardware-configuration.nix (generated on a VM) from accidentally
  # enabling VirtualBox guest additions on a bare-metal host. Guest additions
  # fail to build against linuxPackages_latest (kernel 6.12+).
  virtualisation.virtualbox.guest.enable = lib.mkForce false;
  system.nixos.distroName = "VexOS Desktop NVIDIA";
}
