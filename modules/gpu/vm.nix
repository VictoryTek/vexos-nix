# modules/gpu/vm.nix
# Virtual machine guest: QEMU/KVM guest agent, VirtualBox guest additions,
# SPICE clipboard/auto-resize, virtio-gpu + QXL driver.
# Import this in hosts/vm.nix.
{ config, lib, ... }:
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

  # Load virtio-gpu, QXL display drivers, and VirtIO block device driver early.
  # virtio_blk must be forced into the initrd: the NixOS live ISO has it built-in
  # (not modular), so nixos-generate-config omits it from availableKernelModules.
  # Without it, /dev/vda never appears in the initrd and neededForBoot mounts fail.
  boot.initrd.kernelModules = [ "virtio_gpu" "virtio_blk" ];
  boot.kernelModules        = [ "qxl" ];

  # In a VM the hypervisor manages power — override to performance governor
  powerManagement.cpuFreqGovernor = lib.mkForce "performance";

  # VM btrfs layout is not snapper-compatible — disable btrfs/snapper integration.
  vexos.btrfs.enable = false;

  # scx requires kernel >= 6.12; VM is pinned to 6.6 LTS — disable SCX scheduler.
  services.scx.enable = lib.mkForce false;

  # VMs rely on hypervisor memory management — no disk swap file needed.
  vexos.swap.enable = false;

  # Disable ZFS in VM builds. zfs-server.nix sets boot.supportedFilesystems.zfs = true
  # which causes NixOS to create zfs-import.target and make display-manager.service
  # wait for it. On VM guests with no ZFS pools the import target can fail or hang,
  # preventing GDM from ever starting (black screen on boot).
  boot.supportedFilesystems.zfs = lib.mkForce false;
  services.zfs.autoScrub.enable = lib.mkForce false;
  services.zfs.trim.enable      = lib.mkForce false;

  # Sunshine (modules/sunshine.nix) deliberately has no encoder override here —
  # unlike modules/gpu/{nvidia,amd,intel}.nix. KMS capture on virtio-gpu/QXL is
  # not reliably supported upstream (some setups need a dummy HDMI plug just to
  # have a capturable display surface); forcing a hardware encoder that may not
  # exist would hard-fail instead of falling back. Leave encoder unset so
  # Sunshine auto-detects, falling back to software encoding. Live-test on
  # actual VM hardware before relying on this for unattended access.

}
