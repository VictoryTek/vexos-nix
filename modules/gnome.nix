# modules/gnome.nix
# GNOME desktop: GDM Wayland, XDG portals, fonts, Ozone env var, printing, Bluetooth,
# GNOME tooling, and GNOME Shell extensions.
{ config, pkgs, lib, ... }:
let
  # ── GNOME Flatpak app lists ────────────────────────────────────────────────
  # Apps installed on every role.
  gnomeBaseApps = [
    "org.gnome.TextEditor"
    "org.gnome.Loupe"
    "org.gnome.Totem"
  ];

  # Apps installed only on the Desktop role.
  gnomeDesktopOnlyApps = [
    "org.gnome.Calculator"
    "org.gnome.Calendar"
    "org.gnome.Papers"
    "org.gnome.Snapshot"
  ];

  # Final list for this role.
  gnomeAppsToInstall =
    gnomeBaseApps
    ++ lib.optionals (config.vexos.branding.role == "desktop") gnomeDesktopOnlyApps;

  # Short hash of the app list — changes when the list changes, invalidating
  # the old stamp so the service re-runs and syncs (same pattern as flatpak.nix).
  gnomeAppsHash = builtins.substring 0 16
    (builtins.hashString "sha256" (lib.concatStringsSep "," gnomeAppsToInstall));
in
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
  services.xserver.enable = true;
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
  programs.dconf.profiles.user = {
    enableUserDb = true;
    databases = [
      {
        settings = let
          role = config.vexos.branding.role;
          accentColor = {
            desktop   = "blue";
            htpc      = "orange";
            server    = "yellow";
            stateless = "teal";
          }.${role};
          # Extensions shared by all roles (no gamemode).
          commonExtensions = [
            "appindicatorsupport@rgcjonas.gmail.com"
            "dash-to-dock@micxgx.gmail.com"
            "AlphabeticalAppGrid@stuarthayhurst"
            "gnome-ui-tune@itstime.tech"
            "nothing-to-say@extensions.gnome.wouter.bolsterl.ee"
            "steal-my-focus-window@steal-my-focus-window"
            "tailscale-status@maxgallup.github.com"
            "caffeine@patapon.info"
            "restartto@tiagoporsch.github.io"
            "blur-my-shell@aunetx"
            "background-logo@fedorahosted.org"
          ];
          # Desktop role adds the GameMode indicator.
          enabledExtensions =
            if role == "desktop"
            then commonExtensions ++ [ "gamemodeshellextension@trsnaqe.com" ]
            else commonExtensions;
          # Role-specific dock favorites. Defined here so they are present in
          # the system dconf database before home-manager activation runs —
          # critical on the stateless role where the user dconf db starts empty
          # on every boot due to impermanence (autoLogin fires before HM writes
          # ~/.config/dconf/user).
          favApps = {
            desktop   = [
              "brave-browser.desktop"
              "app.zen_browser.zen.desktop"
              "org.gnome.Nautilus.desktop"
              "com.mitchellh.ghostty.desktop"
              "io.github.up.desktop"
              "org.gnome.Boxes.desktop"
              "code.desktop"
            ];
            stateless = [
              "brave-browser.desktop"
              "torbrowser.desktop"
              "app.zen_browser.zen.desktop"
              "org.gnome.Nautilus.desktop"
              "com.mitchellh.ghostty.desktop"
              "io.github.up.desktop"
            ];
            htpc = [
              "brave-browser.desktop"
              "app.zen_browser.zen.desktop"
              "tv.plex.PlexDesktop.desktop"
              "io.freetubeapp.FreeTube.desktop"
              "org.gnome.Nautilus.desktop"
              "io.github.up.desktop"
              "com.mitchellh.ghostty.desktop"
              "system-update.desktop"
            ];
            server = [
              "brave-browser.desktop"
              "app.zen_browser.zen.desktop"
              "org.gnome.Nautilus.desktop"
              "com.mitchellh.ghostty.desktop"
              "io.github.up.desktop"
            ];
          }.${role};
        in {
          # ── GNOME Shell ─────────────────────────────────────────────────
          "org/gnome/shell" = {
            enabled-extensions = enabledExtensions;
            favorite-apps = favApps;
          };

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
            accent-color = accentColor;
          };

          # ── Window manager ──────────────────────────────────────────────
          "org/gnome/desktop/wm/preferences" = {
            button-layout = "appmenu:minimize,maximize,close";
          };

          # ── Dock ────────────────────────────────────────────────────────
          "org/gnome/shell/extensions/dash-to-dock" = {
            dock-position = "LEFT";
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
          };
          # ── Housekeeping ────────────────────────────────────────────────
          "org/gnome/settings-daemon/plugins/housekeeping" = {
            donation-reminder-enabled = false;
          };        };
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
    user   = "nimda";
  };

  # ── XDG Desktop Portal ────────────────────────────────────────────────────
  # Required for screen sharing, file pickers, and other portal features.
  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-gnome
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
  environment.gnome.excludePackages = with pkgs; [
    gnome-photos
    gnome-tour
    gnome-connections
    gnome-weather
    gnome-clocks
    gnome-contacts
    gnome-maps
    gnome-characters
    gnome-user-docs
    yelp
    simple-scan
    epiphany    # GNOME Web
    geary       # GNOME email client
    xterm
    gnome-music
    rhythmbox
    totem         # Flatpak org.gnome.Totem is installed instead (auto-updated by Up)
    showtime      # GNOME 49 video player ("Video Player") — duplicate of Flatpak Totem
    gnome-calculator  # Flatpak org.gnome.Calculator installed on desktop only
    gnome-calendar    # Flatpak org.gnome.Calendar installed on desktop only
    snapshot          # GNOME Camera — Flatpak org.gnome.Snapshot installed on desktop only
  ] ++ lib.optionals (config.vexos.branding.role != "desktop") [
    papers            # Flatpak org.gnome.Papers installed on desktop only
  ];

  # ── GNOME tooling & Shell extensions ─────────────────────────────────────
  environment.systemPackages = with pkgs; [
    # GNOME tooling
    unstable.gnome-tweaks                               # GNOME customisation GUI
    unstable.dconf-editor                               # Low-level GNOME settings editor
    unstable.gnome-extension-manager                    # Install/manage GNOME Shell extensions

    # Cursor and icon theme packages — must be in system packages so the
    # system dconf profile (programs.dconf.profiles.user.databases) can
    # reference them before home-manager activation completes.
    bibata-cursors
    kora-icon-theme

    # GNOME Shell extensions
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

  # ── GNOME default app Flatpaks ────────────────────────────────────────────
  # Installs GNOME apps from Flathub on first boot (stamp is role+app-list-hash based).
  # Calculator and Calendar are desktop role only; TextEditor, Loupe, Papers,
  # and Totem are installed on all roles.  After initial install, Up manages updates.
  # Skipped entirely when vexos.flatpak.enable = false (e.g. VM guests).
  systemd.services.flatpak-install-gnome-apps = lib.mkIf config.services.flatpak.enable {
    description = "Install GNOME Flatpak apps (once)";
    wantedBy    = [ "multi-user.target" ];
    after       = [ "flatpak-install-apps.service" ];
    requires    = [ "flatpak-add-flathub.service" ];
    path        = [ pkgs.flatpak ];
    script = ''
      STAMP="/var/lib/flatpak/.gnome-apps-installed-${gnomeAppsHash}"
      if [ -f "$STAMP" ]; then exit 0; fi

      # Require at least 1.5 GB free before attempting installs.
      # Exit 0 (not 1) so the switch doesn't fail — stamp is not written,
      # so the service will retry on the next boot.
      AVAIL_MB=$(df /var/lib/flatpak --output=avail -BM 2>/dev/null | tail -1 | tr -d 'M ' || echo 0)
      if [ "$AVAIL_MB" -lt 1536 ]; then
        echo "flatpak: only ''${AVAIL_MB} MB free — need 1536 MB; skipping this boot"
        exit 0
      fi

      ${lib.optionalString (config.vexos.branding.role != "desktop") ''
      # Migration: uninstall desktop-only apps from non-desktop roles.
      for app in ${lib.concatStringsSep " " gnomeDesktopOnlyApps}; do
        if flatpak list --app --columns=application 2>/dev/null | grep -qx "$app"; then
          echo "flatpak: removing desktop-only app $app (role: ${config.vexos.branding.role})"
          flatpak uninstall --noninteractive --assumeyes "$app" || true
        fi
      done
      ''}
      flatpak install --noninteractive --assumeyes flathub \
        ${lib.concatStringsSep " \\\n        " gnomeAppsToInstall}

      rm -f /var/lib/flatpak/.gnome-apps-installed \
            /var/lib/flatpak/.gnome-apps-installed-*
      touch "$STAMP"
    '';
    unitConfig = {
      StartLimitIntervalSec = 600;
      StartLimitBurst       = 10;
    };
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
      Restart         = "on-failure";
      RestartSec      = 60;
    };
  };

  # ── Fonts ─────────────────────────────────────────────────────────────────
  fonts = {
    enableDefaultPackages = true;
    packages = with pkgs; [
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-color-emoji  # renamed from noto-fonts-emoji
      liberation_ttf
      fira-code
      fira-code-symbols
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
