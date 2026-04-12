# hosts/server-vm.nix
# vexos — Server VM guest build (QEMU/KVM + VirtualBox).
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-server-vm
{ lib, ... }:
{
  imports = [
    ../configuration-server.nix
    ../modules/gpu/vm.nix
  ];

  networking.hostName = lib.mkDefault "vexos";

  system.nixos.distroName = "VexOS Server VM";
}
