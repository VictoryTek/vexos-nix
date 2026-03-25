# modules/packages.nix
# Third-party and supplementary Nix packages — installed system-wide.
# Covers the Brave browser, GNOME tooling, and GNOME Shell extensions
# that are not part of the default GNOME desktop environment.
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [

    # ── Browser ───────────────────────────────────────────────────────────────
    unstable.brave                                      # Chromium-based browser

    # ── GNOME tooling ──────────────────────────────────────────────────────────
    unstable.gnome-tweaks                               # GNOME customisation GUI
    unstable.gnome-extension-manager                   # Install/manage GNOME Shell extensions
    unstable.dconf-editor                               # Low-level GNOME settings editor
    unstable.gnome-boxes                                # Virtual machine manager

    # ── GNOME Shell extensions ─────────────────────────────────────────────────
    unstable.gnomeExtensions.appindicator               # System tray icons
    unstable.gnomeExtensions.dash-to-dock               # macOS-style dock
    unstable.gnomeExtensions.alphabetical-app-grid      # Sort app grid alphabetically
    unstable.gnomeExtensions.gamemode-shell-extension   # GameMode status indicator
    unstable.gnomeExtensions.gnome-40-ui-improvements   # UI tweaks
    unstable.gnomeExtensions.nothing-to-say             # Mic mute indicator
    unstable.gnomeExtensions.steal-my-focus-window      # Force window focus
    unstable.gnomeExtensions.tailscale-status           # Tailscale tray indicator
    unstable.gnomeExtensions.caffeine                   # Prevent screen sleep
    unstable.gnomeExtensions.restart-to                 # Restart-to menu entry
    unstable.gnomeExtensions.blur-my-shell              # Blur effects for shell UI
    unstable.gnomeExtensions.background-logo            # Desktop background logo
  ];
}
