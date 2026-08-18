# modules/gpu/vm-guest-additions.nix
# Kernel selection for VM guest variants, plus the VirtualBox Guest Additions fix.
# Imported by modules/gpu/vm.nix and modules/gpu/vanilla-vm.nix.
{ lib, pkgs, ... }:
let
  # virtualboxGuestAdditions does not build against ANY kernel packaged in our
  # nixpkgs pin (verified 6.6 / 6.12 / 6.18 / 7.1). Its vboxvideo module calls
  # drm_fb_helper_alloc_info(), removed from the DRM fbdev helpers; the build dies
  # on -Wint-conversion. meta.broken is false, so nixpkgs gives no warning.
  #
  # This is NOT avoidable via virtualisation.virtualbox.guest.use3rdPartyModules
  # = false: that option only gates boot.extraModulePackages. The package is still
  # referenced unconditionally by environment.systemPackages, systemd.services.
  # virtualbox, the VBoxClient user services, and mount.vboxsf — so it is always
  # built.
  #
  # Upstream's own Makefile already excludes vboxvideo on new kernels, but gates on
  # `uname -r` — the BUILD HOST's running kernel, not the target kernel — which is
  # meaningless inside a Nix sandbox (it reports a pre-7 release, so the gate always
  # opens). Forcing KERN_MAJ high uses that same upstream mechanism to drop
  # vboxvideo from the all/install/clean targets. Everything else still builds:
  # VBoxService, VBoxClient, VBoxControl, VBoxDRMClient, mount.vboxsf, vboxguest.ko
  # and vboxsf.ko. Display handling falls to the in-tree vboxvideo DRM driver,
  # mainline since kernel 4.13 — which is what use3rdPartyModules = false already
  # selects anyway.
  #
  # Remove this override once nixpkgs ships a virtualboxGuestAdditions that builds
  # unpatched; --replace-fail makes a stale substitution a hard error, not a no-op.
  withFixedGuestAdditions = kernelPackages:
    kernelPackages.extend (lfinal: lprev: {
      virtualboxGuestAdditions = lprev.virtualboxGuestAdditions.overrideAttrs (old: {
        postPatch = (old.postPatch or "") + ''
          for mk in src/vboxguest-*/Makefile; do
            substituteInPlace "$mk" \
              --replace-fail 'KERN_MAJ = $(shell uname -r | cut -d . -f1)' 'KERN_MAJ = 99'
          done
        '';
      });
    });
in
{
  # The fix must be an overlay rather than an extension of boot.kernelPackages:
  # nixos/modules/tasks/filesystems/vboxsf.nix builds mount.vboxsf from
  # `pkgs.linuxPackages.virtualboxGuestAdditions` — the DEFAULT kernel package set,
  # ignoring boot.kernelPackages entirely. Both sets therefore need patching:
  # linuxPackages for mount.vboxsf, linuxPackages_6_12 for everything the
  # virtualbox-guest module pulls from boot.kernelPackages.
  nixpkgs.overlays = [
    (final: prev: {
      linuxPackages = withFixedGuestAdditions prev.linuxPackages;
      linuxPackages_6_12 = withFixedGuestAdditions prev.linuxPackages_6_12;
    })
  ];

  # Pin to Linux 6.12 LTS (maintained until Dec 2026).
  # lib.mkForce (priority 50) is required, not decorative: modules/zfs-server.nix
  # sets boot.kernelPackages with lib.mkOverride 75, which outranks both
  # modules/system.nix (mkDefault) and modules/system-lts-kernel.nix (priority 100).
  # Without mkForce the server VM variant silently inherits pkgs.linuxPackages.
  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_6_12;
}
