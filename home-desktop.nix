# home-desktop.nix
# Home Manager configuration for user "nimda".
# Manages user-level packages, shell, GNOME dconf settings, GTK theming, and cursors.
# Consumed by the homeManagerModule in flake.nix via home-manager.users.nimda.
{ config, pkgs, lib, inputs, ... }:
{
  imports = [
    ./home/bash-common.nix
    ./home/photogimp.nix
    ./home/gnome-common.nix
  ];

  photogimp.enable = true;

  home.username    = "nimda";
  home.homeDirectory = "/home/nimda";

  # ── User packages ──────────────────────────────────────────────────────────
  home.packages = with pkgs; [
    # Development tools
    # NOTE: VS Code is installed as unstable.vscode-fhs in modules/development.nix
    # (FHS env required for VS Code to launch correctly on NixOS).
    rustup
    unstable.nodejs_25  # pinned to unstable for latest LTS

    # Terminal emulator
    ghostty

    # Terminal utilities
    tree
    ripgrep
    fd
    bat
    eza
    fzf
    wl-clipboard  # Wayland clipboard CLI (wl-copy / wl-paste)
    # NOTE: just is installed system-wide via modules/packages-common.nix.

    # System utilities
    fastfetch
    blivet-gui
    # NOTE: btop and inxi are installed system-wide via modules/packages-common.nix.

    # NOTE: pavucontrol and protonplus are installed via Flatpak (see modules/flatpak.nix).
    # brave is installed as a Nix package (see modules/packages-common.nix).
  ];

  # ── Starship prompt ────────────────────────────────────────────────────────
  programs.starship = {
    enable = true;
    enableBashIntegration = true;
  };

  xdg.configFile."starship.toml".source = ./files/starship.toml;

  # ── Direnv (per-directory environments) ────────────────────────────────────
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  # ── Tmux terminal multiplexer ──────────────────────────────────────────────
  programs.tmux = {
    enable       = true;
    mouse        = true;
    terminal     = "tmux-256color";
    prefix       = "C-a";
    baseIndex    = 1;
    escapeTime   = 0;
    historyLimit = 10000;
    keyMode      = "vi";
  };

  # ── Justfile ───────────────────────────────────────────────────────────────
  # Deploy the repo's justfile to ~/justfile so 'just' works from home dir.
  # The justfile itself uses readlink -f to resolve its real location so that
  # {{justfile_directory()}} never incorrectly resolves to ~/.
  home.file."justfile".source = ./justfile;

  # ── Hidden app grid entries ────────────────────────────────────────────────
  # These packages cannot be safely removed (they are required dependencies),
  # so their .desktop files are masked to keep them out of the app grid.
  xdg.desktopEntries."org.gnome.Extensions" = {
    name      = "Extensions";
    noDisplay = true;
    settings.Hidden = "true";
  };
  xdg.desktopEntries."xterm" = {
    name      = "XTerm";
    noDisplay = true;
  };
  xdg.desktopEntries."uxterm" = {
    name      = "UXTerm";
    noDisplay = true;
  };

  # ── Session environment variables ─────────────────────────────────────────
  # NIXOS_OZONE_WL: forces Electron apps (VS Code, etc.) to use the Wayland backend.
  # MOZ_ENABLE_WAYLAND: forces Firefox/Zen to use the Wayland backend.
  # QT_QPA_PLATFORM: ensures Qt apps prefer Wayland with XCB as fallback.
  home.sessionVariables = {
    NIXOS_OZONE_WL     = "1";
    MOZ_ENABLE_WAYLAND = "1";
    QT_QPA_PLATFORM    = "wayland;xcb";
  };

  # ── Wallpapers ─────────────────────────────────────────────────────────────
  # Copied from the repo into ~/Pictures/Wallpapers/ at each activation.
  home.file."Pictures/Wallpapers/vex-bb-light.jxl".source = ./wallpapers/desktop/vex-bb-light.jxl;
  home.file."Pictures/Wallpapers/vex-bb-dark.jxl".source  = ./wallpapers/desktop/vex-bb-dark.jxl;

  # ── GNOME dconf defaults ─────────────────────────────────────────────────
  # All dconf keys are set via the system dconf database in modules/gnome.nix
  # and modules/gnome-desktop.nix.  The system-db provides defaults; user
  # changes in GNOME Settings survive rebuilds because the user-db has higher
  # priority.

  # ── State version ──────────────────────────────────────────────────────────
  # Do NOT change after first activation — tracks the HM release at initial install.
  home.stateVersion = "24.05";
}
