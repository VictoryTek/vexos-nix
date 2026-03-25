# home.nix
# Home Manager configuration for user "nimda".
# Manages user-level packages, shell, GNOME dconf settings, GTK theming, and cursors.
# Consumed by the homeManagerModule in flake.nix via home-manager.users.nimda.
{ config, pkgs, lib, inputs, ... }:
{
  imports = [
    ./home/photogimp.nix
  ];

  photogimp.enable = true;

  home.username    = "nimda";
  home.homeDirectory = "/home/nimda";

  # ── User packages ──────────────────────────────────────────────────────────
  home.packages = with pkgs; [
    # Development tools
    vscode
    rustup
    unstable.nodejs_25  # pinned to unstable for latest LTS

    # Terminal emulator
    ghostty

    # Communication
    discord

    # Terminal utilities
    tree
    ripgrep
    fd
    bat
    eza
    fzf
    tmux
    just

    # Themes (must be Nix — consumed by gtk.iconTheme / home.pointerCursor)
    bibata-cursors
    kora-icon-theme

    # System utilities
    fastfetch
    btop
    inxi
    blivet-gui

    # TODO: add the 'up' flake input (e.g. inputs.up.url = "github:...") and uncomment:
    # inputs.up.packages.${pkgs.stdenv.hostPlatform.system}.default

    # NOTE: brave, pavucontrol, protonplus are installed via Flatpak
    # (see modules/flatpak.nix). Moving GUI apps to Flatpak avoids local compilation.
  ];

  # ── Shell ──────────────────────────────────────────────────────────────────
  programs.bash = {
    enable = true;
    shellAliases = {
      ll  = "ls -la";
      ".." = "cd ..";

      # Tailscale shortcuts
      ts   = "tailscale";
      tss  = "tailscale status";
      tsip = "tailscale ip";

      # System service shortcuts
      sshstatus = "systemctl status sshd";
      smbstatus = "systemctl status smbd";
    };
  };

  # ── Starship prompt ────────────────────────────────────────────────────────
  programs.starship = {
    enable = true;
    enableBashIntegration = true;
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

  # ── Cursor (X11 + Wayland) ─────────────────────────────────────────────────
  # Writes env vars, xcursor, and .icons/default.
  # GTK cursor is handled below to prevent activation-script conflicts.
  home.pointerCursor = {
    name    = "Bibata-Modern-Classic";
    package = pkgs.bibata-cursors;
    size    = 24;
  };

  # ── GTK theming ────────────────────────────────────────────────────────────
  # Writes gtk-3/4 config files for non-GNOME apps.
  # Both iconTheme and cursorTheme declared together to prevent conflicts
  # between Home Manager's pointer-cursor activation scripts and dconf settings.
  gtk.enable = true;
  gtk.iconTheme = {
    name    = "kora";
    package = pkgs.kora-icon-theme;
  };
  gtk.cursorTheme = {
    name    = "Bibata-Modern-Classic";
    package = pkgs.bibata-cursors;
    size    = 24;
  };

  # ── Wallpapers ─────────────────────────────────────────────────────────────
  # Copied from the repo into ~/Pictures/Wallpapers/ at each activation.
  # JXL format requires a gdk-pixbuf loader; add jxl-pixbuf-loader (or equivalent)
  # to environment.systemPackages in modules/desktop.nix if wallpapers don't appear.
  # TODO: add wallpaper files to a wallpapers/ directory at the repo root, then uncomment:
  # home.file."Pictures/Wallpapers/vex-bb-light.jxl".source = ./wallpapers/vex-bb-light.jxl;
  # home.file."Pictures/Wallpapers/vex-bb-dark.jxl".source  = ./wallpapers/vex-bb-dark.jxl;

  # ── State version ──────────────────────────────────────────────────────────
  # Do NOT change after first activation — tracks the HM release at initial install.
  home.stateVersion = "24.05";
}
