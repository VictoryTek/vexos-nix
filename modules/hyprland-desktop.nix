# modules/hyprland-desktop.nix
# Hyprland compositor + DankMaterialShell (DMS) desktop shell + DMS greeter, for
# the desktop role. Active only when vexos.desktop.environment == "hyprland"
# (see modules/desktop-environment.nix).
#
# hyprland.conf is not written or managed HERE, but home/dank-material-shell.nix
# seeds a minimal DMS-focused config to ~/.config/hypr/hyprland.conf ONCE on
# first boot (DMS's launcher/lock/clipboard are `dms ipc call` targets with no
# bar button, so an unconfigured Hyprland is unusable). After first boot the
# file is user-owned. Compositor tuning and a fuller keybind set are a later
# customisation phase — the tools they bind to (hyprshot, brightnessctl,
# playerctl, hyprpicker) are installed and ready.
#
# Layer split:
#   • system (this file) — compositor, greeter, and the services/apps GNOME
#     supplied implicitly that DMS does not replace
#   • user   (home/dank-material-shell.nix) — the DMS shell itself, its systemd
#     user service and settings surface, the seeded hyprland.conf, plus the
#     polkit agent and automounter
#   • flake  (flake.nix dmsBase) — the single `dms` flake input and its two
#     NixOS modules (dank-material-shell option tree + greeter). DMS ships no
#     overlays. Modules in this repo stay pure and never take `inputs`.
#
# DE-agnostic content (fonts, printing, Bluetooth, Moonlight, base XDG portal
# enable) comes from modules/desktop-common.nix, imported transitively via
# modules/gnome.nix's import list (present regardless of DE, only its `config`
# is gated).
#
# No remote-desktop setup here — Sunshine/Moonlight (modules/sunshine.nix) is
# the project's remote-access solution across all desktop environments.
{ config, pkgs, lib, ... }:
let
  isHyprland = config.vexos.desktop.environment == "hyprland";
in
{
  config = lib.mkIf isHyprland {
    # ── Compositor ──────────────────────────────────────────────────────────
    programs.hyprland = {
      enable          = true;
      xwayland.enable = true;
      withUWSM        = true;
    };

    # UWSM is load-bearing here, not cosmetic. It is what activates
    # graphical-session.target, and DMS's Home Manager service (dms.service)
    # binds to that target (via config.wayland.systemd.target). Launched from a
    # display manager WITHOUT UWSM, Hyprland never activates the target and the
    # shell silently never starts — you get a bare compositor with no bar,
    # launcher or notifications. Same applies to hyprpolkitagent and udiskie.
    #
    # programs.hyprland.withUWSM = true only sets programs.uwsm.enable — it does
    # NOT register Hyprland with UWSM. Session entries are generated solely from
    # programs.uwsm.waylandCompositors, as <name>-uwsm.desktop; nixpkgs' own
    # option docs say "You must configure waylandCompositors suboptions as well
    # so that UWSM knows which compositors to manage." Without this block the
    # attrset is empty, no hyprland-uwsm.desktop is ever produced, and anything
    # asking UWSM to start that session fails with nothing on screen.
    #
    # NOTE: the greeter therefore lists TWO Hyprland sessions — "Hyprland"
    # (hyprland.desktop, registered by programs.hyprland via
    # services.displayManager.sessionPackages) and "Hyprland (UWSM)"
    # (hyprland-uwsm.desktop). SELECT THE UWSM ONE. Picking the other yields a
    # working compositor with no shell.
    programs.uwsm.waylandCompositors.hyprland = {
      prettyName = "Hyprland";
      binPath    = "${config.programs.hyprland.package}/bin/Hyprland";
    };

    # ── Greeter ─────────────────────────────────────────────────────────────
    # The DMS greeter is a greetd greeter that runs Hyprland ITSELF as its
    # compositor (compositor.name = "hyprland" resolves the package from
    # config.programs.hyprland.package). Its greeter UI ships inside the
    # dms-shell package. The upstream module (flake.nix dmsBase →
    # inputs.dms.nixosModules.greeter) does the greetd wiring itself: it sets
    # services.greetd.settings.default_session.command (mkDefault) to the
    # generated greeter script and reads the greetd user for an assertion.
    # We therefore do NOT declare services.greetd ourselves — a second
    # definition would collide.
    programs.dank-material-shell.greeter = {
      enable             = true;
      compositor.name    = "hyprland";
      quickshell.package = pkgs.quickshell;
    };

    # accounts-daemon: the greeter reads the system user list through it. GNOME
    # pulled this in implicitly. Set it here so the DMS greeter shows real
    # accounts regardless of whether its own module happens to enable it.
    services.accounts-daemon.enable = true;

    # ── Secret Service (hard dependency) ─────────────────────────────────────
    # DMS relies on a Secret Service provider for stored credentials (VPN, some
    # widgets). Under GNOME this came free with the desktop; on Hyprland it must
    # be enabled explicitly.
    services.gnome.gnome-keyring.enable = true;
    programs.seahorse.enable            = true;

    # ── Auto-login ────────────────────────────────────────────────────────────
    # GNOME-equivalent: modules/gnome.nix sets the same services.displayManager
    # options for GDM. The DMS greeter module (inputs.dms.nixosModules.greeter)
    # reads this standard option directly and wires it into greetd's
    # initial_session, resolving the session command via
    # services.displayManager.sessionData.autologinSession — which in turn
    # comes from defaultSession. It must name the UWSM session (see the
    # "SELECT THE UWSM ONE" comment on programs.uwsm.waylandCompositors.hyprland
    # above) or autologin boots a bare compositor with no shell, same as
    # picking the wrong entry manually in the greeter.
    services.displayManager.autoLogin = {
      enable = true;
      user   = config.vexos.user.name;
    };
    services.displayManager.defaultSession = "hyprland-uwsm";

    # Unlock the GNOME Keyring on auto-login. Mirrors
    # security.pam.services.gdm-autologin.enableGnomeKeyring in modules/gnome.nix:
    # a no-op for the actual autologin bypass (no password material to unlock
    # with), kept for interactive re-logins (e.g. after loginctl
    # terminate-session) through the "greetd" PAM service.
    security.pam.services.greetd.enableGnomeKeyring = true;

    # ── Network share discovery (Nautilus "Network" sidebar) ─────────────────
    # Same key and rationale as modules/gnome.nix — GVfs (not GNOME Shell)
    # reads this, and Nautilus is installed for Hyprland too (see
    # environment.systemPackages below). Declared separately here since this
    # module does not import modules/gnome.nix's system dconf profile.
    programs.dconf.profiles.user = {
      enableUserDb = true;
      databases = [
        {
          settings."org/gnome/system/dns-sd".display-local = "merged";
        }
      ];
    };

    # ── Services GNOME supplied implicitly ──────────────────────────────────
    # gvfs: network/trash/mtp backends Nautilus depends on.
    # udisks2: required by udiskie (home/dank-material-shell.nix) for removable media.
    # dconf: GTK apps and nwg-look read settings through it.
    # upower: battery/power state, consumed by DMS's control center.
    services.gvfs.enable    = true;
    services.udisks2.enable = true;
    services.upower.enable  = true;
    programs.dconf.enable   = true;

    # ── XDG Desktop Portal ──────────────────────────────────────────────────
    # xdg-desktop-portal-hyprland is added automatically by programs.hyprland
    # (nixpkgs programs/wayland/hyprland.nix sets
    # xdg.portal.extraPortals = [ cfg.portalPackage ]), so it is NOT repeated
    # here. Only the GTK backend needs adding, for the file chooser and the
    # Settings interface GTK apps query for theme/font preferences.
    xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    xdg.portal.config.common.default = [ "hyprland" "gtk" ];

    # ── Fonts DMS renders its UI with ──────────────────────────────────────
    # DMS draws every bar/menu icon from Material Symbols Rounded and sets its
    # UI text in Inter. Without these the shell shows tofu boxes for all icons.
    # Kept here (not modules/desktop-common.nix) — that file is the DE-agnostic
    # base and these are needed only for the DMS shell.
    fonts.packages = [
      pkgs.material-symbols
      pkgs.inter
    ];

    # ── Packages ────────────────────────────────────────────────────────────
    # DankMaterialShell provides: top bar, control center, notification center,
    # spotlight launcher, app drawer, clipboard viewer, process list, dank dash,
    # notepad, lock screen, OSDs, dynamic Material-You theming, wallpaper, tray,
    # calendar, audio visualiser, night mode. waybar / fuzzel / swaync /
    # hyprpaper / hyprlock / nm-applet are therefore deliberately NOT installed —
    # they would duplicate it.
    #
    # hypridle is likewise omitted: DMS ships its own lock screen and idle
    # handling, and a second idle manager risks double-locking. Revisit only if
    # idle-to-lock turns out not to work.
    environment.systemPackages = with pkgs; [
      # Screenshot / colour picking — DMS does not cover these
      hyprshot
      grim
      slurp
      hyprpicker
      wl-clipboard              # CLI copy/paste
      cliphist                  # clipboard-history store backend DMS's viewer reads

      # Settings panels that GNOME Settings used to provide
      nwg-look                  # GTK theme / icon / font / cursor
      nwg-displays              # monitor arrangement for Hyprland
      pavucontrol               # per-app audio routing

      # Hyprland runtime integrations used by the seeded keybinds / DMS widgets
      brightnessctl
      ddcutil
      playerctl
      jq                         # cursor-zoom keybind (hyprctl getoption -j | jq)
      upower                     # battery-status keybind CLI (daemon alone doesn't guarantee $PATH)

      # File management
      nautilus
      file-roller

      # GNOME utilities — these run fine outside GNOME Shell
      gnome-disk-utility
      gnome-system-monitor
      baobab
      gnome-font-viewer
      gnome-logs

      # GTK app support outside GNOME: schemas and the fallback icon theme that
      # GNOME Shell would otherwise pull in. Without these, GTK apps warn about
      # missing settings schemas and fall back to broken icons.
      gsettings-desktop-schemas
      adwaita-icon-theme
    ];

    # ── Default-app Flatpaks (parity with the GNOME desktop role) ───────────
    # Same app set as modules/gnome-desktop.nix. The option and its service are
    # declared by modules/gnome-flatpak-install.nix, which modules/gnome.nix
    # imports unconditionally (only gnome.nix's `config` is gated), and the
    # service activates on services.flatpak.enable && apps != [] with no GNOME
    # gate — so setting it here works.
    # NOTE: the vexos.gnome.* namespace is historically misnamed for this use;
    # renaming it would touch all four gnome-<role>.nix files. Tech debt.
    vexos.gnome.flatpakInstall.apps = [
      "org.gnome.TextEditor"
      "org.gnome.Loupe"
      "org.gnome.Calculator"
      "org.gnome.Calendar"
      "org.gnome.Papers"
      "org.gnome.Snapshot"
    ];
  };
}
