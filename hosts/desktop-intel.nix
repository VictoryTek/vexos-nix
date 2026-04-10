# hosts/intel.nix
# vexos — Intel GPU desktop build (integrated iGPU or Arc A-series discrete).
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-desktop-intel
{ lib, ... }:
{
  imports = [
    ../configuration.nix
    ../modules/gpu/intel.nix
  ];

  # Prevent hardware-configuration.nix (generated on a VM) from accidentally
  # enabling VirtualBox guest additions on a bare-metal host. Guest additions
  # fail to build against linuxPackages_latest (kernel 6.12+).
  virtualisation.virtualbox.guest.enable = lib.mkForce false;
  system.nixos.distroName = "VexOS Desktop Intel";
}
