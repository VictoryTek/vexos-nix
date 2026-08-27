# modules/gpu/vm-guest-additions.nix
# VM guest platform selection, plus the VirtualBox-specific guest additions,
# their build fix, and the kernel pin they require.
# Imported by modules/gpu/vm.nix and modules/gpu/vanilla-vm.nix — the only file
# both share, so it is where vexos.vm.platform is declared.
#
# Everything in the `config` block below is VirtualBox-only. QEMU/KVM/Proxmox
# guests (the default) skip all of it and keep their role's own kernel:
# linuxPackages_latest on desktop/stateless, the LTS pin on htpc, and so on.
{ config, lib, pkgs, ... }:
let
  isVirtualBox = config.vexos.vm.platform == "virtualbox";

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
  options.vexos.vm.platform = lib.mkOption {
    type = lib.types.enum [ "qemu" "virtualbox" ];
    default = "qemu";
    description = ''
      Hypervisor family this VM guest runs under.

      "qemu" (default) covers QEMU/KVM, Proxmox and libvirt: enables the QEMU
      guest agent and SPICE vdagent, and leaves boot.kernelPackages to the
      role's own kernel module.

      "virtualbox" enables the VirtualBox Guest Additions (shared folders,
      clipboard, auto-resize, drag & drop) and pins the kernel to 6.18 LTS,
      which those additions require in order to build.

      Set per-host in /etc/nixos/features.nix; written by the installer's
      hypervisor prompt when the VM variant is selected.
    '';
  };

  config = lib.mkIf isVirtualBox {
    # The fix must be an overlay rather than an extension of boot.kernelPackages:
    # nixos/modules/tasks/filesystems/vboxsf.nix builds mount.vboxsf from
    # `pkgs.linuxPackages.virtualboxGuestAdditions` — the DEFAULT kernel package set,
    # ignoring boot.kernelPackages entirely. Both sets therefore need patching:
    # linuxPackages for mount.vboxsf, linuxPackages_6_18 for everything the
    # virtualbox-guest module pulls from boot.kernelPackages. The patch itself is
    # kernel-version-agnostic (it just strips a broken out-of-tree build target),
    # so it applies unchanged to whichever kernel is pinned below.
    nixpkgs.overlays = [
      (final: prev: {
        linuxPackages = withFixedGuestAdditions prev.linuxPackages;
        linuxPackages_6_18 = withFixedGuestAdditions prev.linuxPackages_6_18;
      })
    ];

    # VirtualBox guest additions — shared folders, clipboard, auto-resize, drag & drop.
    # use3rdPartyModules = false loads the vboxguest/vboxsf/vboxvideo drivers already
    # mainlined into the kernel rather than VirtualBox's out-of-tree copies. It selects
    # which modules are LOADED; it does not stop the guest-additions package from being
    # BUILT — see withFixedGuestAdditions above for that.
    virtualisation.virtualbox.guest.enable = true;
    virtualisation.virtualbox.guest.dragAndDrop = true;
    virtualisation.virtualbox.guest.use3rdPartyModules = false;

    # Pin to Linux 6.18 LTS (kernel.org extended LTS support to Dec 2028 for both
    # 6.12 and 6.18 in Feb 2026 — 6.18 is the newer of the two, same support
    # window). This pin exists to keep virtualboxGuestAdditions building, which is
    # why it is scoped to the VirtualBox platform: QEMU/Proxmox guests never build
    # that package and have no reason to give up their role's kernel for it.
    # lib.mkForce (priority 50) is required, not decorative: modules/zfs-server.nix
    # sets boot.kernelPackages with lib.mkOverride 75, which outranks both
    # modules/system.nix (mkDefault) and modules/system-lts-kernel.nix (priority 100).
    # Without mkForce the server VM variant silently inherits pkgs.linuxPackages.
    boot.kernelPackages = lib.mkForce pkgs.linuxPackages_6_18;
  };
}
