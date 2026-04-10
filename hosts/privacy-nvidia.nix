# hosts/privacy-nvidia.nix
# vexos — Privacy NVIDIA GPU build (no gaming, development, virtualization, or ASUS modules).
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-privacy-nvidia
{ lib, ... }:
{
  imports = [
    ../configuration-privacy.nix
    ../modules/gpu/nvidia.nix
  ];

  # Prevent hardware-configuration.nix (generated on a VM) from accidentally
  # enabling VirtualBox guest additions on a bare-metal host. Guest additions
  # fail to build against linuxPackages_latest (kernel 6.12+).
  virtualisation.virtualbox.guest.enable = lib.mkForce false;
  system.nixos.distroName = "VexOS Privacy NVIDIA";
}
