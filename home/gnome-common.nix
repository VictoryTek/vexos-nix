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
  # These keys are identical across all roles. Role-specific keys (wallpaper
  # URIs, enabled-extensions, favorite-apps, app-folders) remain in each
  # role's home file.
  dconf.settings = {

    "org/gnome/desktop/interface" = {
      clock-format = "12h";
      cursor-theme = "Bibata-Modern-Classic";
      icon-theme   = "kora";
      color-scheme = "prefer-dark";
    };

    "org/gnome/desktop/wm/preferences" = {
      button-layout = "appmenu:minimize,maximize,close";
    };

    # Wallpaper: use the stable Nix store path from branding.nix's vexosWallpapers
    # package so the value matches the system dconf database entry exactly.
    # The role-specific wallpaper is deployed to this path at build time.
    "org/gnome/desktop/background" = {
      picture-options  = "zoom";
      picture-uri      = "file:///run/current-system/sw/share/backgrounds/vexos/vex-bb-light.jxl";
      picture-uri-dark = "file:///run/current-system/sw/share/backgrounds/vexos/vex-bb-dark.jxl";
    };

    "org/gnome/shell/extensions/dash-to-dock" = {
      dock-position = "LEFT";
    };

    "org/fedorahosted/background-logo-extension" = {
      logo-file           = "/run/current-system/sw/share/pixmaps/vex-background-logo.svg";
      logo-file-dark      = "/run/current-system/sw/share/pixmaps/vex-background-logo-dark.svg";
      logo-always-visible = true;
    };

    "org/gnome/desktop/screensaver" = {
      lock-enabled = false;
      lock-delay   = lib.gvariant.mkUint32 0;
    };

    "org/gnome/session" = {
      idle-delay = lib.gvariant.mkUint32 300;
    };

    "org/gnome/settings-daemon/plugins/housekeeping" = {
      donation-reminder-enabled = false;
    };

  };

  # ── Default browser ────────────────────────────────────────────────────────
  # Declaratively registers Brave as the XDG MIME default for all web schemes
  # so that link-opens from any app use Brave regardless of role or rebuild.
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
}
