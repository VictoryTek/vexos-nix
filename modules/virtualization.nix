# modules/virtualization.nix
# QEMU/KVM virtualisation: libvirt daemon, virt-manager GUI, UEFI/TPM support,
# SPICE USB redirection, and VirtIO drivers for Windows guests.
{ pkgs, ... }:
{
  # ── libvirt / KVM ─────────────────────────────────────────────────────────
  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package      = pkgs.qemu_kvm;      # KVM-enabled QEMU (hardware acceleration)
      runAsRoot    = false;               # Run QEMU as the calling user (safer)
      swtpm.enable = true;               # Virtual TPM 2.0 (required for Windows 11 guests)
      # ovmf is no longer configurable; all OVMF images are available by default in NixOS 25.05+
    };
  };

  # USB passthrough inside SPICE console sessions
  virtualisation.spiceUSBRedirection.enable = true;

  # ── libvirt group ─────────────────────────────────────────────────────────
  # Grants nimda permission to manage VMs without sudo.
  users.users.nimda.extraGroups = [ "libvirtd" ];

  environment.systemPackages = with pkgs; [

    # ── VM management ─────────────────────────────────────────────────────────
    virt-manager                                  # GUI for creating and managing VMs
    virt-viewer                                   # Lightweight SPICE / VNC VM console
    virtio-win                                    # VirtIO drivers ISO for Windows guests

  ];
}
