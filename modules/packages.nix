# modules/packages.nix
# Third-party and supplementary Nix packages — installed system-wide.
# Covers the Brave browser.
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [

    # ── Browser ───────────────────────────────────────────────────────────────
    brave                                              # Chromium-based browser

    # ── System Info ───────────────────────────────────────────────────────────
    inxi                                               # System information tool
    git
    curl
    wget
    htop

  ];
}