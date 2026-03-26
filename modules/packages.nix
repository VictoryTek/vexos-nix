# modules/packages.nix
# Third-party and supplementary Nix packages — installed system-wide.
# Covers the Brave browser.
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [

    # ── Browser ───────────────────────────────────────────────────────────────
    unstable.brave                                      # Chromium-based browser

  ];
}
