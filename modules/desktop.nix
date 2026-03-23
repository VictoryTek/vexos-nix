# modules/desktop.nix
# GNOME desktop: GDM Wayland, XDG portals, fonts, Ozone env var, printing, Bluetooth.
{ config, pkgs, lib, ... }:
{
  # ── GNOME desktop ─────────────────────────────────────────────────────────
  services.xserver.enable = true;
  services.xserver.desktopManager.gnome.enable = true;

  # ── GDM display manager ───────────────────────────────────────────────────
  services.displayManager.gdm = {
    enable = true;
    wayland = true; # Wayland session (default in GNOME 46+ / NixOS 24.11)
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
    epiphany  # GNOME Web — most users prefer Firefox/Chromium
    geary     # GNOME email client
  ];

  # ── Desktop packages ──────────────────────────────────────────────────────
  environment.systemPackages = with pkgs; [
    gnome-tweaks              # GNOME customisation GUI
    gnome-extension-manager  # Install/manage GNOME Shell extensions
    dconf-editor              # Low-level GNOME settings editor
    gnomeExtensions.appindicator # System tray icons (Steam, Discord, etc.)
  ];

  # ── Fonts ─────────────────────────────────────────────────────────────────
  fonts = {
    enableDefaultPackages = true;
    packages = with pkgs; [
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-emoji
      liberation_ttf
      fira-code
      fira-code-symbols
      (nerdfonts.override { fonts = [ "FiraCode" "JetBrainsMono" ]; })
    ];
    fontconfig.defaultFonts = {
      serif     = [ "Noto Serif" ];
      sansSerif = [ "Noto Sans" ];
      monospace = [ "FiraCode Nerd Font" ];
    };
  };

  # ── Printing ──────────────────────────────────────────────────────────────
  services.printing.enable = true;

  # ── Bluetooth ─────────────────────────────────────────────────────────────
  hardware.bluetooth.enable = true;
  services.blueman.enable = true;
}
