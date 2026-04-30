# modules/packages-desktop.nix
# GUI packages for roles with a display server (desktop, server, htpc, stateless).
# Do NOT import on headless-server.
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    brave  # Chromium-based browser
    joplin-desktop  # Note-taking app (testing)
    jdk21  # Java 21 (LTS)
  ];
}
