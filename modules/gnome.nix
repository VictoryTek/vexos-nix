# modules/gnome.nix
# GNOME desktop: GDM Wayland, XDG portals, fonts, Ozone env var, printing, Bluetooth,
# GNOME tooling, and GNOME Shell extensions.
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

    # The GNOME Extensions app (org.gnome.Extensions) is bundled inside
    # gnome-shell and cannot be removed via excludePackages.  Drop its desktop
    # file so it never appears in the app grid.  This overlay runs after the
    # unstable-pin overlay above, so prev.gnome-shell is already the unstable
    # build and overrideAttrs extends it correctly.
    (final: prev: {
      gnome-shell = prev.gnome-shell.overrideAttrs (old: {
        postInstall = (old.postInstall or "") + ''
          rm -f $out/share/applications/org.gnome.Extensions.desktop
        '';
      });
    })
  ];

  # ── GNOME desktop ─────────────────────────────────────────────────────────
  services.xserver.enable = true;
  services.desktopManager.gnome.enable = true;

  # Explicitly enable dconf so the GIO dconf module is loaded and
  # ~/.config/dconf/user is consulted by GLib for all user settings.
  # The GNOME NixOS module also sets this implicitly, but declaring it here
  # makes the dependency explicit and guards against upstream changes.
  programs.dconf.enable = true;

  # Declare the user dconf profile so NixOS generates /etc/dconf/profile/user.
  # This makes the lookup chain declarative: user-db:user (home-manager writes
  # to ~/.config/dconf/user).  Add system-db entries here if system-level
  # defaults or lock overrides are needed in the future.
  programs.dconf.profiles.user = {
    enableUserDb = true;
    databases    = [];
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

  # ── GNOME tooling & Shell extensions ─────────────────────────────────────
  environment.systemPackages = with pkgs; [
    # GNOME tooling
    unstable.gnome-tweaks                               # GNOME customisation GUI
    unstable.gnome-extension-manager                   # Install/manage GNOME Shell extensions
    unstable.dconf-editor                               # Low-level GNOME settings editor
    unstable.gnome-boxes                                # Virtual machine manager

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
  # Installs GNOME apps from Flathub on first boot only
  # (stamp: /var/lib/flatpak/.gnome-apps-installed).
  # After initial install, Up manages updates.
  systemd.services.flatpak-install-gnome-apps = {
    description = "Install GNOME Flatpak apps (once)";
    wantedBy    = [ "multi-user.target" ];
    after       = [ "flatpak-install-apps.service" ];
    requires    = [ "flatpak-add-flathub.service" ];
    path        = [ pkgs.flatpak ];
    script = ''
      if [ -f /var/lib/flatpak/.gnome-apps-installed ]; then exit 0; fi
      flatpak install --noninteractive --assumeyes flathub \
        org.gnome.TextEditor \
        org.gnome.Calculator \
        org.gnome.Calendar \
        org.gnome.Loupe \
        org.gnome.Papers \
        org.gnome.Totem
      touch /var/lib/flatpak/.gnome-apps-installed
    '';
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
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
