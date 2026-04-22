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
    "org.onlyoffice.desktopeditors"             # Office suite
    "org.prismlauncher.PrismLauncher"           # Minecraft launcher
    "com.vysp3r.ProtonPlus"                     # Proton/Wine version manager
    "net.lutris.Lutris"                          # Game manager / Wine frontend
    "com.ranfdev.DistroShelf"                   # Distribution browser
  ];
}
