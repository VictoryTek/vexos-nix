# modules/gpu/vanilla-vm.nix
# Virtual machine guest for the vanilla role.
# Same guest settings as modules/gpu/vm.nix, but without vexos.btrfs.enable
# and vexos.swap.enable — those options are declared in modules/system.nix
# which the vanilla role intentionally does not import (vanilla is a stock
# NixOS baseline with no custom modules).
{ config, lib, ... }:
let
  isQemu = config.vexos.vm.platform == "qemu";
in
{
  # Declares vexos.vm.platform; carries the VirtualBox guest additions and the
  # 6.18 kernel pin they require, both gated on platform == "virtualbox".
  imports = [ ./vm-guest-additions.nix ];

  # QEMU/KVM guest agent — graceful shutdown, memory ballooning, clock sync, file copy
  services.qemuGuest.enable = isQemu;

  # SPICE vdagent — clipboard sync and automatic display resize in SPICE sessions
  services.spice-vdagentd.enable = isQemu;

  # Load virtio-gpu and QXL display drivers early
  boot.initrd.kernelModules = [ "virtio_gpu" ];
  boot.kernelModules        = [ "qxl" ];

  # In a VM the hypervisor manages power — override to performance governor
  powerManagement.cpuFreqGovernor = lib.mkForce "performance";

  # Note: vexos.btrfs.enable and vexos.swap.enable are intentionally omitted.
  # The vanilla role does not import modules/system.nix, so those options
  # are not declared in this evaluation context.
}
