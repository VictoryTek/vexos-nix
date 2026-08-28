# home/gnome-common-browser.nix
# Shared addition for every GNOME DE role that installs brave-origin
# (desktop, server, htpc, stateless — see modules/packages-desktop.nix):
# registers Brave Origin as the XDG MIME default browser. Not imported by
# vanilla (no custom packages) or headless-server (no GNOME).
{ pkgs, ... }:
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

  # ── Clear stale cross-host Brave profile lock ─────────────────────────────
  # Brave/Chromium writes ~/.config/BraveSoftware/<profile>/SingletonLock as a
  # symlink whose target is "<hostname>-<pid>", removed on clean shutdown. An
  # unclean exit (display-manager restart during `nixos-rebuild switch`, crash,
  # power loss) leaves it behind.
  #
  # On the next launch Brave parses that target:
  #   * hostname == current  -> it checks whether <pid> is alive and silently
  #     replaces a dead lock. This already works; leave it alone.
  #   * hostname != current  -> it assumes the profile is on shared storage in
  #     use by another machine, refuses to start, and defers to an unlock
  #     dialog. NixOS GNOME has no zenity/kdialog/xmessage, so Brave just exits
  #     0 with no window — a silent failure.
  #
  # Every VexOS host boots with networking.hostName defaulting to "vexos" before
  # hosts/*.nix renames it, so any machine that ran Brave once pre-rename ends
  # up with a permanently-fatal "vexos-<pid>" lock. This unit removes only the
  # cross-host case, and only when no Brave process is running for the user.
  # See .github/docs/subagent_docs/brave_stale_profile_lock_spec.md
  systemd.user.services.vexos-brave-clear-stale-lock = {
    Unit = {
      Description = "VexOS: clear stale cross-host Brave profile lock";
      After       = [ "graphical-session.target" ];
      PartOf      = [ "graphical-session.target" ];
    };
    Service = {
      Type            = "oneshot";
      RemainAfterExit = true;
      ExecStart       = toString (pkgs.writeShellScript "vexos-brave-clear-stale-lock" ''
        set -u

        # Chromium compares against net::GetHostName(), the short host name.
        HOST="$(${pkgs.hostname}/bin/hostname)"

        # Never touch anything while a Brave process is running for this user
        # (both brave and brave-origin exec a binary named "brave").
        if ${pkgs.procps}/bin/pgrep -u "$UID" -x brave >/dev/null 2>&1; then
          exit 0
        fi

        for profile in \
          "$HOME/.config/BraveSoftware/Brave-Origin" \
          "$HOME/.config/BraveSoftware/Brave-Browser"; do

          lock="$profile/SingletonLock"
          [ -L "$lock" ] || continue

          target="$(${pkgs.coreutils}/bin/readlink "$lock")"   # "<host>-<pid>"
          lockhost="''${target%-*}"

          # Only the fatal cross-host case. Same-host stale locks are Brave's
          # own responsibility and must be left untouched.
          [ -n "$lockhost" ] && [ "$lockhost" != "$HOST" ] || continue

          ${pkgs.coreutils}/bin/rm -f \
            "$profile/SingletonLock" \
            "$profile/SingletonCookie" \
            "$profile/SingletonSocket"
        done

        exit 0
      '');
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
