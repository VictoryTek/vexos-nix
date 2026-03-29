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
# linux-bazzite.nix (vex-kernels, locked rev d612bf28) does not declare
# `features`, `randstructSeed`, or `kernelPatches` in its function signature
# and does not set passthru.features.  NixOS nixpkgs 25.11 kernel.nix always
# calls kernel.override { features; randstructSeed; kernelPatches } and also
# accesses super.kernel.features.  Without the fix both would fail.
# CONFIG_IA32_EMULATION=y and CONFIG_EFI_STUB=y are present in the Fedora
# gaming config that Bazzite uses, so the declared feature values are correct.
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
  #
  # References inputs.kernel-bazzite.packages directly so the store path matches
  # exactly what Garnix CI built and cached from the vex-kernels repo.  Re-deriving
  # via pkgs.callPackage would use vexos-nix's nixos-25.11 pkgs instead of
  # vex-kernels' nixos-unstable pkgs, producing a different store path and a
  # guaranteed cache miss on every rebuild.
  #
  # features (ia32Emulation, efiBootStub) are added via overrideAttrs because
  # linux-bazzite.nix (locked rev d612bf28) does not set passthru.features.
  # The lib.makeOverridable wrapper absorbs the NixOS kernel.nix override args
  # (features, randstructSeed, kernelPatches) without forwarding them upstream.
  boot.kernelPackages = lib.mkOverride 49 (
    let
      # linux-bazzite.nix (vex-kernels, locked rev d612bf28) does not declare
      # `features`, `randstructSeed`, or `kernelPatches` in its function
      # signature, and does not set passthru.features.  NixOS nixpkgs 25.11
      # kernel.nix always calls kernel.override { features; randstructSeed;
      # kernelPatches } — see nixos/modules/system/boot/kernel.nix:67.
      #
      # Fix part 1: add passthru.features so lib.recursiveUpdate
      #   super.kernel.features features does not throw "attribute missing".
      #   overrideAttrs with passthru-only changes preserves the .drv store
      #   path, so Garnix-cached builds are still used.
      #
      # Fix part 2: wrap with lib.makeOverridable using a function that accepts
      #   features/randstructSeed/kernelPatches via `...`, so the .override
      #   call does not reach the strict 5-arg linux-bazzite.nix function.
      rawKernel = inputs.kernel-bazzite.packages.x86_64-linux.linux-bazzite;
      kernelWithFeatures = rawKernel.overrideAttrs (old: {
        passthru = (old.passthru or {}) // {
          features = {
            ia32Emulation = true;  # CONFIG_IA32_EMULATION=y — Fedora gaming config
            efiBootStub   = true;  # CONFIG_EFI_STUB=y       — Fedora gaming config
          };
        };
      });
      bazziteKernel = lib.makeOverridable
        ({ features ? {}, randstructSeed ? "", kernelPatches ? [], ... }:
          kernelWithFeatures)
        {};
    in
    pkgs.linuxPackagesFor bazziteKernel
  );

  # Distinguish the VM host on the network
  networking.hostName = "vexos-vm";
}
