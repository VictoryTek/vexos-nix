# hosts/server-vm.nix
# vexos — Server VM guest build (QEMU/KVM + VirtualBox).
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-server-vm
{ inputs, ... }:
{
  imports = [
    ../configuration-server.nix
    ../modules/gpu/vm.nix
  ];

  networking.hostName = "vexos-server-vm";

  environment.systemPackages = [
    inputs.up.packages.x86_64-linux.default
  ];
  system.nixos.distroName = "VexOS Server VM";
}
