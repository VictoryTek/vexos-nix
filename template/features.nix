# /etc/nixos/features.nix
# Optional feature toggles for this VexOS host.
# Managed by `just enable-feature <feature>` / `just disable-feature <feature>`.
# After editing, run `just rebuild` to apply.
#
# Available features (desktop role):
#   gaming        — Steam, Proton-GE, GameMode, Gamescope, Wine, controllers,
#                   32-bit GPU libs, SCX LAVD scheduler, gaming kernel params
#   development   — Docker, VSCodium, Python, Node, Go, Claude Code, Nix LSP
#   print3d       — Blender and OrcaSlicer (via Flatpak)
#   virtualization — libvirtd/KVM, QEMU-KVM, GNOME Boxes / virt-manager support
{
  # vexos.features.gaming.enable         = false;
  # vexos.features.development.enable    = false;
  # vexos.features.print3d.enable        = false;
  # vexos.features.virtualization.enable = false;
}
