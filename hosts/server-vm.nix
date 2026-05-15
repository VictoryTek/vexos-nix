# hosts/server-vm.nix
# vexos — Server VM guest build (QEMU/KVM + VirtualBox).
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-server-vm
{ lib, ... }:
{
  imports = [
    ../configuration-server.nix
    ../modules/gpu/vm.nix
  ];

  system.nixos.distroName = "VexOS Server VM";

  # REQUIRED: replace with the real value from the target host.
  # Generate: head -c 8 /etc/machine-id
  networking.hostId = "a0000004";
}
