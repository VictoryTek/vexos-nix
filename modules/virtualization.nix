# modules/virtualization.nix
# Virtualisation stack for the desktop role:
# - libvirtd + QEMU/KVM as the primary hypervisor (GNOME Boxes & virt-manager)
# - VirtualBox disabled: kernel 7.0 moved KVM symbols to a restricted namespace
#   that VirtualBox ≤7.2.6 cannot import. Re-enable when upstream fixes this.
{ pkgs, ... }:
{
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

  # ── User groups ───────────────────────────────────────────────────────────
  # libvirtd  — manage GNOME Boxes VMs without sudo
  users.users.nimda.extraGroups = [ "libvirtd" ];
}
