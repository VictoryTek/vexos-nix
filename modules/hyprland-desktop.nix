# modules/hyprland-desktop.nix
# Hyprland compositor + Noctalia v5 desktop shell + noctalia-greeter, for the
# desktop role. Active only when vexos.desktop.environment == "hyprland" (see
# modules/desktop-environment.nix).
#
# Hyprland itself is deliberately UNCONFIGURED: no hyprland.conf is written,
# managed or seeded here. Hyprland autogenerates its own default at
# ~/.config/hypr/hyprland.conf on first launch. Keybinds and compositor tuning
# are a later customisation phase — the tools they will bind to (hyprshot,
# brightnessctl, playerctl, hyprpicker) are installed and ready.
#
# Layer split:
#   • system (this file) — compositor, greeter, and the services/apps GNOME
#     supplied implicitly that Noctalia does not replace
#   • user   (home/noctalia.nix) — the Noctalia shell itself, its systemd user
#     service, settings and palettes, plus the polkit agent and automounter
#   • flake  (flake.nix noctaliaBase) — the two upstream flake inputs, their
#     overlays (pkgs.noctalia / pkgs.noctalia-greeter) and the greeter's NixOS
#     module. Modules in this repo stay pure and never take `inputs`.
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
    # graphical-session.target, and Noctalia's Home Manager service binds to
    # that target (via config.wayland.systemd.target). Launched from a display
    # manager WITHOUT UWSM, Hyprland never activates the target and the shell
    # silently never starts — you get a bare compositor with no bar, launcher
    # or notifications. Same applies to hyprpolkitagent and udiskie.
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
    # noctalia-greeter is a greetd greeter that runs inside its own bundled
    # wlroots compositor (noctalia-greeter-session), independent of Hyprland.
    # Its upstream NixOS module does the wiring itself: it sets services.greetd
    # (command = noctalia-greeter-session), enables services.accounts-daemon,
    # creates /var/lib/noctalia-greeter, and asserts the greetd user exists.
    # We therefore do NOT declare services.greetd ourselves — a second
    # definition would collide. This replaces the previous Omarchy-style
    # greeterless autologin.
    programs.noctalia-greeter = {
      enable  = true;
      package = pkgs.noctalia-greeter;
    };

    # ── Secret Service (hard dependency) ─────────────────────────────────────
    # Noctalia v5 lists a Secret Service provider as a runtime requirement
    # (BUILDING.md: GNOME Keyring, KWallet or KeePassXC). Under GNOME this came
    # free with the desktop; on Hyprland it must be enabled explicitly.
    services.gnome.gnome-keyring.enable = true;
    programs.seahorse.enable            = true;

    # ── Services GNOME supplied implicitly ──────────────────────────────────
    # gvfs: network/trash/mtp backends Nautilus depends on.
    # udisks2: required by udiskie (home/noctalia.nix) for removable media.
    # dconf: GTK apps and nwg-look read settings through it.
    # upower: battery/power state, consumed by Noctalia's control center.
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

    # ── Packages ────────────────────────────────────────────────────────────
    # Noctalia v5 already provides: bar, widgets, dock, launcher, control
    # center, notifications, wallpaper, lock screen, session actions, clipboard
    # history, OSDs, tray and desktop widgets. waybar / fuzzel / swaync /
    # hyprpaper / hyprlock / cliphist / nm-applet are therefore deliberately
    # NOT installed — they would duplicate it.
    #
    # hypridle is likewise omitted: Noctalia ships its own lock screen and
    # session actions, and a second idle manager risks double-locking. Revisit
    # only if idle-to-lock turns out not to work.
    environment.systemPackages = with pkgs; [
      # Screenshot / colour picking — Noctalia does not cover these
      hyprshot
      grim
      slurp
      hyprpicker
      wl-clipboard              # CLI copy/paste; Noctalia owns clipboard history

      # Settings panels that GNOME Settings used to provide
      nwg-look                  # GTK theme / icon / font / cursor
      nwg-displays              # monitor arrangement for Hyprland
      pavucontrol               # per-app audio routing

      # Noctalia optional runtime integrations (named in its own dependency list)
      brightnessctl
      ddcutil
      playerctl

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
