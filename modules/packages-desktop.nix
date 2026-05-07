# modules/packages-desktop.nix
# GUI packages for roles with a display server (desktop, server, htpc, stateless).
# Do NOT import on headless-server.
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    brave   # Chromium-based browser
    gparted # Graphical disk partition editor (system package so .desktop is resolvable by GNOME)
    joplin-desktop  # Note-taking app (testing)
    jdk21  # Java 21 (LTS)
    mpv    # Video player (replaces Totem Flatpak on desktop/stateless/server)
  ];
}
