# modules/gpu/vm.nix
# Virtual machine guest: QEMU/KVM guest agent, VirtualBox guest additions,
# SPICE clipboard/auto-resize, virtio-gpu + QXL driver.
# Import this in hosts/vm.nix.
{ config, lib, pkgs, ... }:
{
  # Pin to Linux 6.6 LTS — VirtualBox Guest Additions 7.2.4 is incompatible with Linux 6.19
  # (drm_fb_helper_alloc_info was removed). 6.6 LTS is maintained until Dec 2026.
  # lib.mkForce overrides the default set by modules/performance.nix.
  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_6_6;

  # QEMU/KVM guest agent — graceful shutdown, memory ballooning, clock sync, file copy
  services.qemuGuest.enable = true;

  # SPICE vdagent — clipboard sync and automatic display resize in SPICE sessions
  services.spice-vdagentd.enable = true;

  # VirtualBox guest additions — shared folders, clipboard, auto-resize, drag & drop
  virtualisation.virtualbox.guest.enable = true;

  # Load virtio-gpu and QXL display drivers early
  boot.initrd.kernelModules = [ "virtio_gpu" ];
  boot.kernelModules        = [ "qxl" ];

  # In a VM the hypervisor manages power — override to performance governor
  powerManagement.cpuFreqGovernor = lib.mkForce "performance";

  # VM btrfs layout is not snapper-compatible — disable btrfs/snapper integration.
  vexos.btrfs.enable = false;

  # VMs rely on hypervisor memory management — no disk swap file needed.
  vexos.swap.enable = false;

}
