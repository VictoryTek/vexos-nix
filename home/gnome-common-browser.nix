# home/gnome-common-browser.nix
# Shared addition for every GNOME DE role that installs brave-origin
# (desktop, server, htpc, stateless — see modules/packages-desktop.nix):
# registers Brave Origin as the XDG MIME default browser. Not imported by
# vanilla (no custom packages) or headless-server (no GNOME).
{ ... }:
{
  # ── MIME associations ──────────────────────────────────────────────────────
  # Declaratively registers Brave Origin as the XDG MIME default for all web
  # schemes. force = true on both paths ensures Home Manager never stalls on
  # activation when GNOME has already written these files to disk (or a
  # stale .backup exists).
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "x-scheme-handler/http"  = [ "brave-origin.desktop" ];
      "x-scheme-handler/https" = [ "brave-origin.desktop" ];
      "text/html"              = [ "brave-origin.desktop" ];
      "application/xhtml+xml"  = [ "brave-origin.desktop" ];
      "x-scheme-handler/ftp"   = [ "brave-origin.desktop" ];
      "x-scheme-handler/mailto" = [ "brave-origin.desktop" ];
    };
  };
  xdg.configFile."mimeapps.list".force = true;
  xdg.dataFile."applications/mimeapps.list".force = true;
}
