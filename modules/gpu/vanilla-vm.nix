# modules/gpu/vanilla-vm.nix
# Virtual machine guest for the vanilla role.
# Same guest additions and kernel settings as modules/gpu/vm.nix, but
# without vexos.btrfs.enable and vexos.swap.enable — those options are
# declared in modules/system.nix which the vanilla role intentionally does
# not import (vanilla is a stock NixOS baseline with no custom modules).
{ lib, ... }:
{
  # Kernel pin (6.12 LTS) + VirtualBox Guest Additions build fix.
  imports = [ ./vm-guest-additions.nix ];

  # QEMU/KVM guest agent — graceful shutdown, memory ballooning, clock sync, file copy
  services.qemuGuest.enable = true;

  # SPICE vdagent — clipboard sync and automatic display resize in SPICE sessions
  services.spice-vdagentd.enable = true;

  # VirtualBox guest additions — shared folders, clipboard, auto-resize, drag & drop.
  # use3rdPartyModules = false loads the vboxguest/vboxsf/vboxvideo drivers already
  # mainlined into the kernel rather than VirtualBox's out-of-tree copies. It selects
  # which modules are LOADED; it does not stop the guest-additions package from being
  # BUILT — see ./vm-guest-additions.nix for that. The in-tree drivers only bind when
  # real VirtualBox hardware is present, so this is safe on QEMU/KVM/Proxmox guests.
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
