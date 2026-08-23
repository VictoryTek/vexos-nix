# modules/desktop-common.nix
# DE-agnostic desktop-role additions: fonts, printing, Bluetooth, VPN plugin,
# Moonlight client, and auto-login. Applies regardless of
# vexos.desktop.environment (gnome/cosmic/hyprland) — extracted from
# modules/gnome.nix so COSMIC and Hyprland hosts get the same baseline.
{ config, pkgs, ... }:
{
  # ── Auto-login ────────────────────────────────────────────────────────────
  services.displayManager.autoLogin = {
    enable = true;
    user   = config.vexos.user.name;
  };

  # ── Moonlight client ──────────────────────────────────────────────────────
  # Connect to other machines' Sunshine hosts (modules/sunshine.nix).
  environment.systemPackages = [ pkgs.moonlight-qt ];

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

  # ── NetworkManager VPN plugins ────────────────────────────────────────────
  # Enables .ovpn import via GNOME Settings → VPN and nmcli connection import.
  networking.networkmanager.plugins = [ pkgs.networkmanager-openvpn ];

  # ── Ozone Wayland ─────────────────────────────────────────────────────────
  # Makes Electron/Chromium-based apps use native Wayland rendering.
  # NIXOS_OZONE_WL: nixpkgs wrapper adds --ozone-platform=wayland to Electron args.
  # ELECTRON_OZONE_PLATFORM_HINT: Electron 28+ (VS Code 1.87+) requires this to
  # auto-detect the Wayland backend inside the buildFHSEnvBubblewrap sandbox used
  # by vscode-fhs; without it the app silently exits on Wayland sessions.
  environment.sessionVariables = {
    NIXOS_OZONE_WL               = "1";
    ELECTRON_OZONE_PLATFORM_HINT = "auto";
  };

  # ── XDG Desktop Portal ────────────────────────────────────────────────────
  # Base enable shared by every DE; each DE module adds its own portal backend
  # package (extraPortals).
  xdg.portal.enable = true;
}
