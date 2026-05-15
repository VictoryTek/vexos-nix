# hosts/vanilla-vm.nix
# vexos — Vanilla VM guest build (stock NixOS baseline).
# Includes minimal guest additions for VM usability (QEMU, SPICE, VirtualBox).
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-vanilla-vm
{ lib, pkgs, ... }:
{
  imports = [
    ../configuration-vanilla.nix
  ];

  # ── VM guest additions ─────────────────────────────────────────────────────
  # These are infrastructure for the VM to be functional, not an opinion.
  # Without them: no clipboard sync, no display resize, no graceful shutdown.

  # QEMU/KVM guest agent — graceful shutdown, memory ballooning, clock sync
  services.qemuGuest.enable = true;

  # SPICE vdagent — clipboard sync and automatic display resize
  services.spice-vdagentd.enable = true;

  # VirtualBox guest additions — shared folders, clipboard, auto-resize
  virtualisation.virtualbox.guest.enable = true;
  virtualisation.virtualbox.guest.dragAndDrop = true;

  system.nixos.distroName = "VexOS Vanilla VM";
}
