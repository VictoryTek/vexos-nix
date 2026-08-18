# modules/gpu/vanilla-vm.nix
# Virtual machine guest for the vanilla role.
# Same guest additions and kernel settings as modules/gpu/vm.nix, but
# without vexos.btrfs.enable and vexos.swap.enable — those options are
# declared in modules/system.nix which the vanilla role intentionally does
# not import (vanilla is a stock NixOS baseline with no custom modules).
{ lib, ... }:
{
  # QEMU/KVM guest agent — graceful shutdown, memory ballooning, clock sync, file copy
  services.qemuGuest.enable = true;

  # SPICE vdagent — clipboard sync and automatic display resize in SPICE sessions
  services.spice-vdagentd.enable = true;

  # VirtualBox guest additions — shared folders, clipboard, auto-resize, drag & drop.
  # use3rdPartyModules = false uses the vboxguest/vboxvideo drivers already mainlined
  # into the kernel instead of compiling VirtualBox's own out-of-tree copy, which lags
  # upstream DRM API changes and fails to build on current kernels (e.g.
  # drm_fb_helper_alloc_info was removed). The in-tree driver only binds when real
  # VirtualBox hardware is present, so this is safe on QEMU/KVM/Proxmox guests too.
  virtualisation.virtualbox.guest.enable = true;
  virtualisation.virtualbox.guest.dragAndDrop = true;
  virtualisation.virtualbox.guest.use3rdPartyModules = false;

  # Load virtio-gpu and QXL display drivers early
  boot.initrd.kernelModules = [ "virtio_gpu" ];
  boot.kernelModules        = [ "qxl" ];

  # In a VM the hypervisor manages power — override to performance governor
  powerManagement.cpuFreqGovernor = lib.mkForce "performance";

  # Note: vexos.btrfs.enable and vexos.swap.enable are intentionally omitted.
  # The vanilla role does not import modules/system.nix, so those options
  # are not declared in this evaluation context.
}
