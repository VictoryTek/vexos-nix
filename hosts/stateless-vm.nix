# hosts/stateless-vm.nix
# vexos — Stateless VM guest build (no gaming, development, virtualization, or ASUS modules).
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-stateless-vm
{ lib, ... }:
{
  imports = [
    ../configuration-stateless.nix
    ../modules/gpu/vm.nix
    ../modules/stateless-disk.nix
  ];

  # VM guests use plain Btrfs (no LUKS — encryption handled by the hypervisor).
  vexos.stateless.disk = {
    enable     = true;
    device     = "/dev/vda";
  };

  system.nixos.distroName = "VexOS Stateless VM";
}
