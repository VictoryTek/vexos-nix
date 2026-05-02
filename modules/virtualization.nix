# modules/virtualization.nix
# Virtualisation stack for the desktop role:
# - VirtualBox as the primary hypervisor (VM creation & management)
# - libvirtd + QEMU/KVM retained as the backend for GNOME Boxes
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

  # ── VirtualBox host ───────────────────────────────────────────────────────
  virtualisation.virtualbox.host = {
    enable              = true;
    enableExtensionPack = true;   # USB 2/3 passthrough (unfree; allowed in modules/nix.nix)
  };

  # ── User groups ───────────────────────────────────────────────────────────
  # libvirtd  — manage GNOME Boxes VMs without sudo
  # vboxusers — access VirtualBox host services
  users.users.nimda.extraGroups = [ "libvirtd" "vboxusers" ];
}
