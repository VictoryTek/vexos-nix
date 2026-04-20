# home-stateless.nix
# Home Manager configuration for user "nimda" — Stateless role.
# Same as desktop minus gaming app folders and dev-only packages (no development.nix on stateless).
{ config, pkgs, lib, inputs, ... }:
{
  imports = [
    ./home/photogimp.nix
    ./home/gnome-common.nix
  ];

  photogimp.enable = true;

  home.username    = "nimda";
  home.homeDirectory = "/home/nimda";

  # ── User packages ──────────────────────────────────────────────────────────
  home.packages = with pkgs; [
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
    # NOTE: just is installed system-wide via modules/packages.nix.

    # System utilities
    fastfetch
    blivet-gui
    # NOTE: btop and inxi are installed system-wide via modules/packages.nix.

    # NOTE: brave is installed as a Nix package (see modules/packages.nix).
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
  home.file."justfile".source = ./justfile;

  # ── Hidden app grid entries ────────────────────────────────────────────────
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
  home.sessionVariables = {
    NIXOS_OZONE_WL     = "1";
    MOZ_ENABLE_WAYLAND = "1";
    QT_QPA_PLATFORM    = "wayland;xcb";
  };

  # ── Wallpapers ─────────────────────────────────────────────────────────────
  home.file."Pictures/Wallpapers/vex-bb-light.jxl".source = ./wallpapers/stateless/vex-bb-light.jxl;
  home.file."Pictures/Wallpapers/vex-bb-dark.jxl".source  = ./wallpapers/stateless/vex-bb-dark.jxl;

  # ── GNOME dconf settings ────────────────────────────────────────────────
  dconf.settings = {

    "org/gnome/shell" = {
      enabled-extensions = [
        "appindicatorsupport@rgcjonas.gmail.com"
        "dash-to-dock@micxgx.gmail.com"
        "AlphabeticalAppGrid@stuarthayhurst"
        # gamemode-shell-extension omitted — programs.gamemode not enabled on stateless
        "gnome-ui-tune@itstime.tech"
        "nothing-to-say@extensions.gnome.wouter.bolsterl.ee"
        "steal-my-focus-window@steal-my-focus-window"
        "tailscale-status@maxgallup.github.com"
        "caffeine@patapon.info"
        "restartto@tiagoporsch.github.io"
        "blur-my-shell@aunetx"
        "background-logo@fedorahosted.org"
      ];
      favorite-apps = [
        "brave-browser.desktop"
        "app.zen_browser.zen.desktop"
        "org.gnome.Nautilus.desktop"
        "com.mitchellh.ghostty.desktop"
        "io.github.up.desktop"
      ];
    };

    "org/gnome/desktop/app-folders" = {
      folder-children = [ "Office" "Utilities" "System" ];
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
        "io.missioncenter.MissionCenter.desktop"
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
        "org.gnome.Logs.desktop"
        "btrfs-assistant.desktop"
        "org.gnome.SystemMonitor.desktop"
      ];
    };
  };

  home.stateVersion = "24.05";
}
