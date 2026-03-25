# modules/desktop.nix
# GNOME desktop: GDM Wayland, XDG portals, fonts, Ozone env var, printing, Bluetooth.
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
      # NOTE: gnome-text-editor, gnome-system-monitor, gnome-calculator,
      # gnome-calendar, loupe, evince/papers, and totem are installed via
      # Flatpak (see modules/flatpak.nix) to avoid local compilation.
    })
  ];

  # ── GNOME desktop ─────────────────────────────────────────────────────────
  services.xserver.enable = true;
  services.desktopManager.gnome.enable = true;

  # ── GDM display manager ───────────────────────────────────────────────────
  services.displayManager.gdm = {
    enable = true;
    wayland = true; # Wayland session (default in GNOME 47+ / NixOS 25.11)
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
  environment.sessionVariables.NIXOS_OZONE_WL = "1";

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
    # Replaced by Flatpak versions (latest from Flathub, avoids local compilation)
    gnome-text-editor
    gnome-system-monitor
    gnome-calculator
    gnome-calendar
    loupe
    # gnome-papers omitted — not yet a top-level pkgs attribute in nixos-25.11
    totem
  ];

  # ── GNOME default app Flatpaks ────────────────────────────────────────────
  # GNOME apps excluded from Nix packages above are installed from Flathub
  # instead, keeping them up-to-date independently of nixpkgs.
  # Runs after flatpak-add-flathub.service (defined in modules/flatpak.nix).
  systemd.services.flatpak-install-gnome-apps = {
    description = "Install GNOME default apps from Flathub";
    wantedBy    = [ "multi-user.target" ];
    after       = [ "flatpak-add-flathub.service" ];
    requires    = [ "flatpak-add-flathub.service" ];
    path        = [ pkgs.flatpak ];
    script      = ''
      flatpak install --noninteractive --assumeyes flathub \
        org.gnome.TextEditor \
        org.gnome.SystemMonitor \
        org.gnome.Calculator \
        org.gnome.Calendar \
        org.gnome.Loupe \
        org.gnome.Papers \
        org.gnome.Totem \
        || true
    '';
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
    };
  };

  # ── Desktop packages ──────────────────────────────────────────────────────
  environment.systemPackages = with pkgs; [
    # GNOME tooling
    unstable.gnome-tweaks              # GNOME customisation GUI
    unstable.gnome-extension-manager  # Install/manage GNOME Shell extensions
    unstable.dconf-editor              # Low-level GNOME settings editor
    unstable.gnome-boxes               # Virtual machine manager

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

  # ── GNOME dconf system defaults ────────────────────────────────────────────
  # Written to the NixOS system dconf database at build time.
  # Does NOT require a D-Bus session, so settings are available at first login.
  # Users can still override these via GNOME Settings or dconf-editor
  # (system DB is not locked; user-db:user takes precedence in the profile).
  programs.dconf.profiles.user.databases = [{
    settings = {
      "org/gnome/shell" = {
        enabled-extensions = [
          "appindicatorsupport@rgcjonas.gmail.com"
          "dash-to-dock@micxgx.gmail.com"
          "AlphabeticalAppGrid@stuarthayhurst"
          "gamemodeshellextension@trsnaqe.com"
          "gnome-ui-tune@itstime.tech"
          "nothing-to-say@extensions.gnome.wouter.bolsterl.ee"
          "steal-my-focus-window@steal-my-focus-window"
          "tailscale-status@maxgallup.github.com"
          "caffeine@patapon.info"
          pkgs.gnomeExtensions.restart-to.extensionUuid
          "blur-my-shell@aunetx"
          "background-logo@fedorahosted.org"
        ];
        favorite-apps = [
          "brave-browser.desktop"
          "app.zen_browser.zen.desktop"
          "org.gnome.Nautilus.desktop"
          "com.mitchellh.ghostty.desktop"
          "io.github.up.desktop"
          "org.gnome.Boxes.desktop"
          "code.desktop"
          "discord.desktop"
        ];
      };
      "org/gnome/desktop/interface" = {
        clock-format = "12h";
        cursor-size  = lib.gvariant.mkInt32 24;
        cursor-theme = "Bibata-Modern-Classic";
        icon-theme   = "kora";
      };
      "org/gnome/desktop/wm/preferences" = {
        button-layout = "appmenu:minimize,maximize,close";
      };
      "org/gnome/desktop/background" = {
        picture-uri      = "file:///home/nimda/Pictures/Wallpapers/vex-bb-light.jxl";
        picture-uri-dark = "file:///home/nimda/Pictures/Wallpapers/vex-bb-dark.jxl";
        picture-options  = "zoom";
      };
      "org/gnome/shell/extensions/dash-to-dock" = {
        dock-position = "LEFT";
      };
      "org/gnome/desktop/screensaver" = {
        lock-enabled = true;
        lock-delay   = lib.gvariant.mkUint32 0;  # lock immediately
      };
      "org/gnome/session" = {
        idle-delay = lib.gvariant.mkUint32 300;  # 5 min inactivity
      };
      "org/gnome/desktop/app-folders" = {
        folder-children = [ "Games" "Office" "Utilities" "System" ];
      };
      "org/gnome/desktop/app-folders/folders/Games" = {
        name = "Games";
        apps = [
          "org.prismlauncher.PrismLauncher.desktop"
          "com.vysp3r.ProtonPlus.desktop"
        ];
      };
      "org/gnome/desktop/app-folders/folders/Office" = {
        name = "Office";
        apps = [
          "org.onlyoffice.desktopeditors.desktop"
          "org.gnome.TextEditor.desktop"
          "org.gnome.Papers.desktop"
        ];
      };
      "org/gnome/desktop/app-folders/folders/Utilities" = {
        name = "Utilities";
        apps = [
          "com.mattjakeman.ExtensionManager.desktop"
          "it.mijorus.gearlever.desktop"
          "org.gnome.tweaks.desktop"
          "io.github.flattool.Warehouse.desktop"
          "io.missioncenter.MissionCenter.desktop"
          "com.github.tchx84.Flatseal.desktop"
        ];
      };
      "org/gnome/desktop/app-folders/folders/System" = {
        name = "System";
        apps = [
          "org.pulseaudio.pavucontrol.desktop"
          "rog-control-center.desktop"
          "org.gnome.SystemMonitor.desktop"
          "org.gnome.Settings.desktop"
          "org.gnome.seahorse.Application.desktop"
          "nixos-manual.desktop"
          "cups.desktop"
          "blivet-gui.desktop"
          "blueman-manager.desktop"
          "btop.desktop"
          "ca.desrt.dconf-editor.desktop"
          "org.gnome.baobab.desktop"
          "org.gnome.DiskUtility.desktop"
          "org.gnome.font-viewer.desktop"
          "htop.desktop"
          "org.gnome.Logs.desktop"
        ];
      };
    };
  }];

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
