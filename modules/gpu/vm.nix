# modules/gpu/vm.nix
# Virtual machine guest: QEMU/KVM guest agent, VirtualBox guest additions,
# SPICE clipboard/auto-resize, virtio-gpu + QXL driver.
# Import this in hosts/vm.nix.
{ config, pkgs, lib, ... }:
{
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

  # LTS kernel baseline — provides a clean build for VirtualBox GuestAdditions
  # and avoids zen/CachyOS overhead in a VM environment.
  # hosts/vm.nix overrides this with the Bazzite kernel via lib.mkOverride 49.
  boot.kernelPackages = lib.mkForce pkgs.linuxPackages;
}
