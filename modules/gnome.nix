# modules/gnome.nix
# Universal GNOME desktop base: GDM Wayland, XDG portal, dconf, GNOME tooling,
# and the role-agnostic GNOME Shell extensions. Active only when
# vexos.desktop.environment == "gnome" (see modules/desktop-environment.nix).
# DE-agnostic content (fonts, printing, Bluetooth, VPN plugin, auto-login,
# Moonlight) lives in modules/desktop-common.nix instead.
#
# Role-specific additions (accent colour, dock favourites, role-only extensions,
# Flatpak install service, extra excludePackages) live in:
#   modules/gnome-desktop.nix
#   modules/gnome-htpc.nix
#   modules/gnome-server.nix
#   modules/gnome-stateless.nix
{ config, pkgs, lib, ... }:
let
  isGnome = config.vexos.desktop.environment == "gnome";
in
{
  imports = [ ./gnome-flatpak-install.nix ./desktop-environment.nix ./desktop-common.nix ];

  options.vexos.gnome.commonExtensions = lib.mkOption {
    type        = lib.types.listOf lib.types.str;
    default     = [
      "appindicatorsupport@rgcjonas.gmail.com"
      "dash-to-dock@micxgx.gmail.com"
      "AlphabeticalAppGrid@stuarthayhurst"
      "gnome-ui-tune@itstime.tech"
      "nothing-to-say@extensions.gnome.wouter.bolsterl.ee"
      "steal-my-focus-window@steal-my-focus-window"
      "tailscale-status@maxgallup.github.com"
      "caffeine@patapon.info"
      "blur-my-shell@aunetx"
      "background-logo@fedorahosted.org"
      "tiling-assistant@leleat-on-github"
    ];
    internal    = true;
    description = "GNOME Shell extensions enabled on every vexos role that imports gnome.nix.";
  };

  options.vexos.gnome.extraExtensions = lib.mkOption {
    type        = lib.types.listOf lib.types.str;
    default     = [];
    internal    = true;
    description = "Additional GNOME Shell extension UUIDs appended to commonExtensions. Set by feature modules (e.g. gaming) so their extensions are only active when the feature is enabled.";
  };

  config = lib.mkIf isGnome {

  # ── GNOME desktop ─────────────────────────────────────────────────────────
  services.xserver.enable = lib.mkDefault true;
  services.xserver.excludePackages = lib.mkDefault [ pkgs.xterm ];
  services.desktopManager.gnome.enable = true;

  # Explicitly enable dconf so the GIO dconf module is loaded and
  # ~/.config/dconf/user is consulted by GLib for all user settings.
  # The GNOME NixOS module also sets this implicitly, but declaring it here
  # makes the dependency explicit and guards against upstream changes.
  programs.dconf.enable = true;

  # Declare the user dconf profile so NixOS generates /etc/dconf/profile/user.
  # The lookup chain is: user-db:user (home-manager) → the system database below.
  # System database is written during nixos-rebuild switch and is available before
  # any user session starts — critical for autoLogin where GNOME reads dconf at
  # session start before home-manager's user activation service completes.
  #
  # Universal keys only — accent-color, enabled-extensions, and favorite-apps
  # are written by the role-specific gnome-<role>.nix module.
  programs.dconf.profiles.user = {
    enableUserDb = true;
    databases = [
      {
        settings = {
          # ── Wallpaper (stable Nix store path via branding.nix) ──────────
          # vexos-wallpapers package deploys the role-specific wallpaper to
          # /run/current-system/sw/share/backgrounds/vexos/ at build time.
          "org/gnome/desktop/background" = {
            picture-uri      = "file:///run/current-system/sw/share/backgrounds/vexos/vex-bb-light.jxl";
            picture-uri-dark = "file:///run/current-system/sw/share/backgrounds/vexos/vex-bb-dark.jxl";
            picture-options  = "zoom";
          };

          # ── Interface (cursor, icon, clock) ────────────────────────────
          "org/gnome/desktop/interface" = {
            cursor-theme = "Bibata-Modern-Classic";
            icon-theme   = "kora";
            clock-format = "12h";
            color-scheme = "prefer-dark";
          };

          # ── Window manager ──────────────────────────────────────────────
          "org/gnome/desktop/wm/preferences" = {
            button-layout = "appmenu:minimize,maximize,close";
          };

          # ── Background logo extension ───────────────────────────────────
          "org/fedorahosted/background-logo-extension" = {
            logo-file           = "/run/current-system/sw/share/pixmaps/vex-background-logo.svg";
            logo-file-dark      = "/run/current-system/sw/share/pixmaps/vex-background-logo-dark.svg";
            logo-always-visible = true;
          };

          "org/gnome/shell/extensions/nothing-to-say" = {
            keybinding-toggle-mute = lib.gvariant.mkEmptyArray lib.gvariant.type.string;
            icon-visibility        = "always";
          };

          # ── Screensaver / session ───────────────────────────────────────
          "org/gnome/desktop/screensaver" = {
            lock-enabled = false;
            lock-delay   = lib.gvariant.mkUint32 0;
          };

          "org/gnome/session" = {
            idle-delay = lib.gvariant.mkUint32 300;
          };

          # ── Housekeeping ────────────────────────────────────────────────
          "org/gnome/settings-daemon/plugins/housekeeping" = {
            donation-reminder-enabled = false;
          };

          # ── Network share discovery (Nautilus "Network" sidebar) ────────
          # Pin GNOME's DNS-SD aggregation behaviour so that locally-
          # discovered mDNS services are merged into the same Network view
          # as remote ones. "merged" is the GNOME 49 schema default; we pin
          # it system-wide so an unexpected upgrade-path stale value in any
          # user database cannot silently hide auto-discovered SMB/NFS/SFTP
          # hosts. vexos builds always run on fresh dconf, so this is purely
          # defensive.
          "org/gnome/system/dns-sd" = {
            display-local = "merged";
          };
        };
      }
    ];
  };

  # ── GDM display manager ───────────────────────────────────────────────────
  services.displayManager.gdm.enable = true;

  # Unlock the GNOME Keyring on auto-login. pam_gnome_keyring is already wired
  # for normal GDM login (password unlocks the keyring); gdm-autologin bypasses
  # PAM password auth so this has no password material to unlock with and is a
  # no-op for auto-login sessions in practice. Kept for interactive re-logins
  # (e.g. after loginctl terminate-session).
  security.pam.services.gdm-autologin.enableGnomeKeyring = true;

  # ── GNOME Remote Desktop (RDP) — disabled ─────────────────────────────────
  # The upstream GNOME NixOS module sets this to mkDefault true. Force it off:
  # this project uses Sunshine/Moonlight (modules/sunshine.nix) for remote
  # access, not GNOME's built-in RDP server.
  services.gnome.gnome-remote-desktop.enable = lib.mkForce false;

  # ── XDG Desktop Portal ────────────────────────────────────────────────────
  # Base xdg.portal.enable comes from modules/desktop-common.nix; this adds
  # the GNOME-specific portal backend.
  xdg.portal.extraPortals = [
    pkgs.xdg-desktop-portal-gnome
  ];

  # ── GNOME bloat reduction ─────────────────────────────────────────────────
  # Common bloat list — applies to every role that imports this module.
  environment.gnome.excludePackages = [
    pkgs.gnome-photos
    pkgs.gnome-tour
    pkgs.gnome-connections
    pkgs.gnome-weather
    pkgs.gnome-clocks
    pkgs.gnome-contacts
    pkgs.gnome-maps
    pkgs.gnome-characters
    pkgs.gnome-user-docs
    pkgs.yelp
    pkgs.simple-scan
    pkgs.epiphany    # GNOME Web
    pkgs.geary       # GNOME email client
    pkgs.xterm
    pkgs.gnome-music
    pkgs.rhythmbox
    pkgs.totem         # mpv (nixpkgs) is the video player; Flatpak Totem is not installed
    pkgs.showtime      # GNOME 49 video player ("Video Player") — duplicate of Flatpak Totem
    pkgs.gnome-calculator  # Flatpak org.gnome.Calculator installed on desktop only
    pkgs.gnome-calendar    # Flatpak org.gnome.Calendar installed on desktop only
    pkgs.snapshot          # GNOME Camera — Flatpak org.gnome.Snapshot installed on desktop only
    pkgs.papers            # winnow 0.7.x fails with rustc 1.91.1; desktop gets Papers via Flatpak
  ];

  # ── GNOME tooling & Shell extensions ─────────────────────────────────────
  # Common extensions only — gamemode-shell-extension is added by
  # modules/gnome-desktop.nix (it is the only role that enables it).
  environment.systemPackages = [
    # GNOME tooling
    pkgs.gnome-tweaks                                        # GNOME customisation GUI
    pkgs.dconf-editor                                        # Low-level GNOME settings editor
    pkgs.gnome-extension-manager                             # Install/manage GNOME Shell extensions

    # Cursor and icon theme packages — must be in system packages so the
    # system dconf profile (programs.dconf.profiles.user.databases) can
    # reference them before home-manager activation completes.
    pkgs.bibata-cursors
    pkgs.kora-icon-theme

    # GNOME Shell extensions — must match the gnome-shell version (stable).
    # gnome-shell is intentionally kept on stable; extensions run inside
    # gnome-shell's JS runtime and are version-checked against it.
    pkgs.gnomeExtensions.appindicator               # System tray icons
    pkgs.gnomeExtensions.dash-to-dock               # macOS-style dock
    pkgs.gnomeExtensions.alphabetical-app-grid      # Sort app grid alphabetically
    pkgs.gnomeExtensions.gnome-40-ui-improvements   # UI tweaks
    pkgs.gnomeExtensions.nothing-to-say             # Mic mute indicator
    pkgs.gnomeExtensions.steal-my-focus-window      # Force window focus
    pkgs.gnomeExtensions.tailscale-status           # Tailscale tray indicator
    pkgs.gnomeExtensions.caffeine                   # Prevent screen sleep
    pkgs.gnomeExtensions.blur-my-shell              # Blur effects for shell UI
    pkgs.gnomeExtensions.background-logo            # Desktop background logo
    pkgs.gnomeExtensions.tiling-assistant           # Half- and quarter-tiling support
  ];

  }; # end config
}
