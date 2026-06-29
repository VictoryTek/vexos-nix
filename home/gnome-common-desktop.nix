# home/gnome-common-desktop.nix
# Desktop-role-only addition: registers Brave Origin as the XDG MIME
# default browser. Split out from home/gnome-common.nix because
# brave-origin (modules/packages-desktop.nix) is only installed on the
# desktop role.
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
    };
  };
  xdg.configFile."mimeapps.list".force = true;
  xdg.dataFile."applications/mimeapps.list".force = true;
}
