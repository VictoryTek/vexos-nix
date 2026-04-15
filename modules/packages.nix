# modules/packages.nix
# Base system packages shared across all roles (desktop, htpc, server, stateless).
# Desktop additionally imports modules/development.nix for dev-specific tooling.
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [

    # ── Browser ───────────────────────────────────────────────────────────────
    brave                                              # Chromium-based browser

    # ── Build / task runner ───────────────────────────────────────────────────
    just                                               # Command runner (justfile)

    # ── System utilities ──────────────────────────────────────────────────────
    btop                                               # Terminal process viewer
    inxi                                               # System information tool
    git                                                # Version control
    curl                                               # HTTP / transfer CLI
    wget                                               # File downloader

  ];
}