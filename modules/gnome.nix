# modules/gnome.nix
# Universal GNOME desktop base: GDM Wayland, XDG portals, fonts, Ozone env var,
# printing, Bluetooth, GNOME tooling, and the role-agnostic GNOME Shell extensions.
#
# Role-specific additions (accent colour, dock favourites, role-only extensions,
# Flatpak install service, extra excludePackages) live in:
#   modules/gnome-desktop.nix
#   modules/gnome-htpc.nix
#   modules/gnome-server.nix
#   modules/gnome-stateless.nix
{ config, pkgs, lib, ... }:
{
  # ── GNOME stack sourced from nixpkgs-unstable ──────────────────────────────
  # Replaces the GNOME desktop shell and its default-shipped applications with
  # the latest builds from nixos-unstable.  Everything else on the system stays
  # on nixos-25.11.  pkgs.unstable is provided by the unstableOverlayModule
  # defined in flake.nix.
  nixpkgs.overlays = [
    (final: prev: let u = final.unstable; in {
      # Core GNOME shell stack
      gnome-shell            = u.gnome-shell;
      mutter                 = u.mutter;
      gdm                    = u.gdm;
      gnome-session          = u.gnome-session;
      gnome-settings-daemon  = u.gnome-settings-daemon;
      gnome-control-center   = u.gnome-control-center;
      gnome-shell-extensions = u.gnome-shell-extensions;

      # Default GNOME applications
      nautilus               = u.nautilus;           # Files
      gnome-console          = u.gnome-console;      # Terminal
      gnome-disk-utility     = u.gnome-disk-utility;
      baobab                 = u.baobab;             # Disk Usage Analyzer
      gnome-software         = u.gnome-software;

      # NOTE: gvfs is NOT pinned to unstable here. Stable gvfs (from nixpkgs
      # 25.05) provides all required backends: dnssd, network, smb,
      # smb-browse, wsdd, nfs, sftp. The unstable pin was previously added
      # for "IPC parity" with unstable Nautilus, but gvfs communicates with
      # Nautilus via D-Bus (not direct linking), so the stable/unstable
      # combination is safe. The unstable gvfs caused the wsdd backend to
      # malfunction, preventing NAS devices from appearing in Nautilus →
      # Network. Reverting to stable gvfs matches default NixOS behaviour,
      # which discovers network shares correctly.
      # NOTE: gnome-text-editor, gnome-system-monitor, loupe, and totem are
      # installed via Flatpak on all roles; gnome-calculator, gnome-calendar,
      # evince/papers, and gnome-snapshot are installed via Flatpak on the
      # desktop role only.
      # (see modules/flatpak.nix) to avoid local compilation.
    })

    # The GNOME Extensions app (org.gnome.Extensions) cannot be removed via
    # excludePackages because it is bundled inside gnome-shell.  Drop its
    # desktop file from BOTH gnome-shell and gnome-shell-extensions so it
    # never appears in the app grid regardless of which package installs it.
    # This overlay runs after the unstable-pin overlay above, so
    # prev.gnome-shell is already the unstable build.
    (final: prev: {
      gnome-shell = prev.gnome-shell.overrideAttrs (old: {
        postInstall = (old.postInstall or "") + ''
          rm -f $out/share/applications/org.gnome.Extensions.desktop
        '';
      });
      gnome-shell-extensions = prev.gnome-shell-extensions.overrideAttrs (old: {
        postInstall = (old.postInstall or "") + ''
          rm -f $out/share/applications/org.gnome.Extensions.desktop
        '';
      });
    })
  ];

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
  services.displayManager.gdm = {
    enable  = true;
    wayland = true; # Wayland session (default in GNOME 47+ / NixOS 25.11)
  };

  # ── Auto-login ────────────────────────────────────────────────────────────
  services.displayManager.autoLogin = {
    enable = true;
    user   = config.vexos.user.name;
  };

  # ── XDG Desktop Portal ────────────────────────────────────────────────────
  # Required for screen sharing, file pickers, and other portal features.
  xdg.portal = {
    enable = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-gnome
    ];
    config.common.default = "gnome";
  };

  # ── Ozone Wayland ─────────────────────────────────────────────────────────
  # Makes Electron/Chromium-based apps use native Wayland rendering.
  # NIXOS_OZONE_WL: nixpkgs wrapper adds --ozone-platform=wayland to Electron args.
  # ELECTRON_OZONE_PLATFORM_HINT: Electron 28+ (VS Code 1.87+) requires this to
  # auto-detect the Wayland backend inside the buildFHSEnvBubblewrap sandbox used
  # by vscode-fhs; without it the app silently exits on Wayland sessions.
  environment.sessionVariables = {
    NIXOS_OZONE_WL             = "1";
    ELECTRON_OZONE_PLATFORM_HINT = "auto";
  };

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
    pkgs.unstable.gnome-tweaks                               # GNOME customisation GUI
    pkgs.unstable.dconf-editor                               # Low-level GNOME settings editor
    pkgs.unstable.gnome-extension-manager                    # Install/manage GNOME Shell extensions

    # Cursor and icon theme packages — must be in system packages so the
    # system dconf profile (programs.dconf.profiles.user.databases) can
    # reference them before home-manager activation completes.
    pkgs.bibata-cursors
    pkgs.kora-icon-theme

    # GNOME Shell extensions
    pkgs.unstable.gnomeExtensions.appindicator               # System tray icons
    pkgs.unstable.gnomeExtensions.dash-to-dock               # macOS-style dock
    pkgs.unstable.gnomeExtensions.alphabetical-app-grid      # Sort app grid alphabetically
    pkgs.unstable.gnomeExtensions.gnome-40-ui-improvements   # UI tweaks
    pkgs.unstable.gnomeExtensions.nothing-to-say             # Mic mute indicator
    pkgs.unstable.gnomeExtensions.steal-my-focus-window      # Force window focus
    pkgs.unstable.gnomeExtensions.tailscale-status           # Tailscale tray indicator
    pkgs.unstable.gnomeExtensions.caffeine                   # Prevent screen sleep
    pkgs.unstable.gnomeExtensions.restart-to                 # Restart-to menu entry
    pkgs.unstable.gnomeExtensions.blur-my-shell              # Blur effects for shell UI
    pkgs.unstable.gnomeExtensions.background-logo            # Desktop background logo
    pkgs.unstable.gnomeExtensions.tiling-assistant           # Half- and quarter-tiling support
  ];

  # ── Fonts ─────────────────────────────────────────────────────────────────
  fonts = {
    enableDefaultPackages = true;
    packages = [
      pkgs.noto-fonts
      pkgs.noto-fonts-cjk-sans
      pkgs.noto-fonts-color-emoji  # renamed from noto-fonts-emoji
      pkgs.liberation_ttf
      pkgs.fira-code
      pkgs.fira-code-symbols
      pkgs.nerd-fonts.fira-code
      pkgs.nerd-fonts.jetbrains-mono
    ];
    fontconfig.defaultFonts = {
      serif     = [ "Noto Serif" ];
      sansSerif = [ "Noto Sans" ];
      monospace = [ "FiraCode Nerd Font Mono" ];
    };
  };

  # ── Printing ──────────────────────────────────────────────────────────────
  services.printing.enable = true;

  # ── Bluetooth ─────────────────────────────────────────────────────────────
  hardware.bluetooth.enable = true;
  services.blueman.enable = true;

}
