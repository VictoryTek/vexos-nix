# modules/virtualization.nix
# Virtualisation stack for the desktop role:
# - libvirtd + QEMU/KVM as the primary hypervisor (GNOME Boxes & virt-manager)
# - VirtualBox disabled: kernel 7.0 moved KVM symbols to a restricted namespace
#   that VirtualBox ≤7.2.6 cannot import. Re-enable when upstream fixes this.
#
# Enable on a per-host basis via /etc/nixos/features.nix:
#   vexos.features.virtualization.enable = true;
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.features.virtualization;
in
{
  options.vexos.features.virtualization.enable = lib.mkEnableOption "virtualization stack (libvirtd, QEMU/KVM, GNOME Boxes support)";

  config = lib.mkIf cfg.enable {
    # ── libvirt / KVM (backend for GNOME Boxes) ───────────────────────────────
    virtualisation.libvirtd = {
      enable = true;
      qemu = {
        package      = pkgs.qemu_kvm;      # KVM-enabled QEMU (hardware acceleration)
        runAsRoot    = false;               # Run QEMU as the calling user (safer)
        swtpm.enable = true;               # Virtual TPM 2.0 (required for Windows 11 guests)
        # ovmf is no longer configurable; all OVMF images are available by default in NixOS 25.05+
      };
    };

    # ── VirtualBox host (DISABLED — incompatible with kernel 7.0) ─────────────
    # virtualisation.virtualbox.host = {
    #   enable              = true;
    #   enableExtensionPack = true;
    # };

    # ── libvirtd socket binding ───────────────────────────────────────────────
    # NixOS drops the upstream PartOf= directive from the libvirtd.service unit,
    # breaking socket-activated restarts during nixos-rebuild switch: new socket
    # units start while the old service is still running, causing a second
    # instance to conflict on the socket and exit with code 1. Restore upstream
    # behaviour so libvirtd stops cleanly whenever its socket units are cycled.
    # KillMode=process (set by NixOS) ensures running QEMU VMs are not affected.
    systemd.services.libvirtd.unitConfig = {
      PartOf = "libvirtd.socket libvirtd-ro.socket libvirtd-admin.socket";
    };

    # ── User groups ───────────────────────────────────────────────────────────
    # libvirtd  — manage GNOME Boxes VMs without sudo
    users.users.${config.vexos.user.name}.extraGroups = [ "libvirtd" ];
  };
}
