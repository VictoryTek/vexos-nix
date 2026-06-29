# modules/flatpak-desktop.nix
# Desktop-role Flatpak additions: gaming, development, and productivity apps.
#
# Import only in configuration-desktop.nix.
# Requires: modules/flatpak.nix (declares vexos.flatpak.extraApps option).
#
# The vexos.flatpak.extraApps list option uses NixOS listOf merge semantics —
# multiple modules may set it and the values are concatenated automatically.
{ ... }:
{
  vexos.flatpak.extraApps = [
    "io.github.pol_rivero.github-desktop-plus"  # GitHub Desktop (community fork)
    "net.cozic.joplin_desktop"                  # Joplin note-taking app
    "org.onlyoffice.desktopeditors"             # Office suite
    "com.ranfdev.DistroShelf"                   # Distribution browser
  ];
}
