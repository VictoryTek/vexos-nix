# hosts/privacy-vm.nix
# vexos — Privacy VM guest build (no gaming, development, virtualization, or ASUS modules).
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-privacy-vm
{ ... }:
{
  imports = [
    ../configuration-privacy.nix
    ../modules/gpu/vm.nix
    ../modules/privacy-disk.nix
  ];

  # VM guests use plain Btrfs (no LUKS — encryption handled by the hypervisor).
  vexos.privacy.disk = {
    enable     = true;
    device     = "/dev/vda";
    enableLuks = false;
  };

  networking.hostName = "vexos-privacy-vm";

  system.nixos.distroName = "VexOS Privacy VM";
}
