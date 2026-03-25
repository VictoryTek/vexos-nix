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
      gnome-text-editor      = u.gnome-text-editor;
      gnome-system-monitor   = u.gnome-system-monitor;
      gnome-calculator       = u.gnome-calculator;
      gnome-calendar         = u.gnome-calendar;
      loupe                  = u.loupe;              # Image Viewer
      evince                 = u.evince;             # Document Viewer
      totem                  = u.totem;              # Videos
      gnome-disk-utility     = u.gnome-disk-utility;
      baobab                 = u.baobab;             # Disk Usage Analyzer
      gnome-software         = u.gnome-software;
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
  ];

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

  # ── Enable GNOME Shell extensions by default ────────────────────────────
  programs.dconf.profiles.user.databases = [{
    settings = {
      "org/gnome/shell" = {
        enabled-extensions = [
          "appindicatorsupport@rgcjonas.gmail.com"
          "dash-to-dock@micxgx.gmail.com"
          "AlphabeticalAppGrid@stuarthayhurst.com"
          "gamemode@christian.kellner.me"
          "gnome-40-ui-improvements@someone_else"
          "nothing-to-say@extensions.gnome.wouter.bolsterl.ee"
          "steal-my-focus-window@koutch.github.io"
          "tailscale-status@maxgallup.github.com"
          "caffeine@patapon.info"
          "restart-to@pratap.fastmail.fm"
          "blur-my-shell@aunetx"
          "background-logo@fedorahosted.org"
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
