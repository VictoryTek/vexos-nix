# modules/packages.nix
# Base system packages for non-desktop roles (server, htpc, stateless).
# Desktop role uses modules/development.nix instead (which includes these plus dev tools).
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [

    # ── Browser ───────────────────────────────────────────────────────────────
    brave                                              # Chromium-based browser

    # ── System utilities ──────────────────────────────────────────────────────
    btop                                               # Terminal process viewer
    inxi                                               # System information tool
    git                                                # Version control
    curl                                               # HTTP / transfer CLI
    wget                                               # File downloader

  ];
}