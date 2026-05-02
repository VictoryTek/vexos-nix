# home/gnome-common.nix
# Shared GNOME theming, cursor/icon settings, and common dconf keys
# applied to ALL roles (desktop, server, htpc, stateless).
# Import this from each role's home file.
{ pkgs, lib, ... }:
{
  # ── Theme packages ─────────────────────────────────────────────────────────
  # Required for gtk.iconTheme and home.pointerCursor declarations below.
  home.packages = with pkgs; [
    bibata-cursors
    kora-icon-theme
  ];

  # ── Cursor (X11 + Wayland) ─────────────────────────────────────────────────
  home.pointerCursor = {
    name    = "Bibata-Modern-Classic";
    package = pkgs.bibata-cursors;
    size    = 24;
  };

  # ── GTK theming ────────────────────────────────────────────────────────────
  # Writes gtk-3/4 config files for non-GNOME apps.
  # Both iconTheme and cursorTheme declared together to prevent conflicts
  # between Home Manager's pointer-cursor activation scripts and dconf settings.
  gtk.enable = true;
  gtk.iconTheme = {
    name    = "kora";
    package = pkgs.kora-icon-theme;
  };
  gtk.cursorTheme = {
    name    = "Bibata-Modern-Classic";
    package = pkgs.bibata-cursors;
    size    = 24;
  };

  # ── Common GNOME dconf settings ────────────────────────────────────────────
  # All GNOME defaults are set via the system dconf database
  # (programs.dconf.profiles.user.databases in modules/gnome.nix and the
  # role-specific gnome-<role>.nix modules).  The system database provides
  # defaults that the user can override — manual customizations survive
  # nixos-rebuild because the user-db has higher priority than the system-db.
  #
  # Previously dconf.settings was used here, but Home Manager writes those
  # directly into ~/.config/dconf/user, overwriting manual changes on every
  # rebuild.  Removed to preserve user customizations.

  # ── MIME associations ──────────────────────────────────────────────────────
  # Declaratively registers Brave as the XDG MIME default for all web schemes.
  # force = true on both paths ensures Home Manager never stalls on activation
  # when GNOME has already written these files to disk (or a stale .backup exists).
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "x-scheme-handler/http"  = [ "brave-browser.desktop" ];
      "x-scheme-handler/https" = [ "brave-browser.desktop" ];
      "text/html"              = [ "brave-browser.desktop" ];
      "application/xhtml+xml"  = [ "brave-browser.desktop" ];
      "x-scheme-handler/ftp"   = [ "brave-browser.desktop" ];
    };
  };
  xdg.configFile."mimeapps.list".force = true;
  xdg.dataFile."applications/mimeapps.list".force = true;
}
