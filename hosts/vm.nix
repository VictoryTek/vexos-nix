# hosts/vm.nix
# vexos — Virtual machine guest build (QEMU/KVM + VirtualBox).
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-vm
#
# Bazzite kernel: applied here for testing purposes only.
# lib.mkOverride 49 is required to override both:
#   - modules/performance.nix (normal priority, CachyOS kernel)
#   - modules/gpu/vm.nix (lib.mkForce / priority 50, LTS kernel)
# Priority 49 < 50, so this definition wins cleanly without a conflict.
#
# features.ia32Emulation = true is declared inside the callPackage wrapper.
# features.efiBootStub = true is declared inside the callPackage wrapper.
# linuxManualConfig does not auto-expose passthru.features; without them the
# hardware.graphics.enable32Bit assertion (graphics.nix:128) and the
# systemd-boot assertion (systemd-boot.nix:533) would both fail.
# Bazzite uses the Fedora gaming config (CONFIG_IA32_EMULATION=y, CONFIG_EFI_STUB=y)
# so both declarations are factually correct.  Placing them inside the wrapper lambda
# ensures they survive any subsequent .override call made by kernel.nix.
#
# Bootloader: NOT configured here — set it in your host's hardware-configuration.nix.
#
# BIOS VM example (add to /etc/nixos/hardware-configuration.nix):
#   boot.loader.systemd-boot.enable = false;
#   boot.loader.grub = { enable = true; device = "/dev/sda"; efiSupport = false; };
#
# UEFI VM example (add to /etc/nixos/hardware-configuration.nix):
#   boot.loader.systemd-boot.enable = false;
#   boot.loader.grub = { enable = true; device = "nodev"; efiSupport = true;
#                        efiInstallAsRemovable = true; };
{ pkgs, lib, inputs, ... }:
{
  imports = [
    ../configuration.nix
    ../modules/gpu/vm.nix
  ];

  # Bazzite kernel — overrides modules/gpu/vm.nix LTS (lib.mkForce/priority 50) and
  # modules/performance.nix CachyOS setting (normal priority).
  # Uses lib.mkOverride 49 (priority 49 < 50) so this definition wins over lib.mkForce
  # without triggering a "defined multiple times" conflict on the unique option.
  boot.kernelPackages = lib.mkOverride 49 (
    pkgs.linuxPackagesFor (
      pkgs.callPackage
        ({ lib, fetchFromGitHub, fetchurl, linuxManualConfig, runCommand
         , features ? {}, ... }:
          let bazziteBase =
                import "${inputs.kernel-bazzite}/pkgs/linux-bazzite.nix"
                  { inherit lib fetchFromGitHub fetchurl linuxManualConfig runCommand; };
          # Declare ia32Emulation so hardware.graphics.enable32Bit assertion passes.
          # Declare efiBootStub so systemd-boot assertion passes.
          # Bazzite uses the Fedora gaming config: CONFIG_IA32_EMULATION=y, CONFIG_EFI_STUB=y.
          # linuxManualConfig does not auto-expose `features`; we add it here so the
          # attribute persists through any subsequent .override calls made by kernel.nix.
          in bazziteBase // { features = (bazziteBase.features or {}) // { ia32Emulation = true; efiBootStub = true; }; })
        {}
    )
  );

  # Distinguish the VM host on the network
  networking.hostName = "vexos-vm";
}
