# home-desktop.nix
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
    # NOTE: just is installed system-wide via modules/packages.nix.

    # Themes (must be Nix — consumed by gtk.iconTheme / home.pointerCursor)
    bibata-cursors
    kora-icon-theme

    # System utilities
    fastfetch
    blivet-gui
    # NOTE: btop and inxi are installed system-wide via modules/packages.nix.

    # NOTE: pavucontrol and protonplus are installed via Flatpak (see modules/flatpak.nix).
    # brave is installed as a Nix package (see modules/packages.nix).
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
  home.file."Pictures/Wallpapers/vex-bb-light.jxl".source = ./wallpapers/desktop/vex-bb-light.jxl;
  home.file."Pictures/Wallpapers/vex-bb-dark.jxl".source  = ./wallpapers/desktop/vex-bb-dark.jxl;

  # ── GNOME dconf settings ────────────────────────────────────────────────
  # Written directly into the user's dconf binary db during home-manager activation.
  # These override system-level defaults and are the authoritative source for all
  # GNOME settings tracked in this repo.
  dconf.settings = {

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
        "org.gnome.Boxes.desktop"
        "code.desktop"
      ];
    };

    "org/gnome/desktop/interface" = {
      clock-format = "12h";
      cursor-size  = 24;
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

    "org/fedorahosted/background-logo-extension" = {
      logo-file         = "/run/current-system/sw/share/pixmaps/vex-background-logo.svg";
      logo-file-dark    = "/run/current-system/sw/share/pixmaps/vex-background-logo-dark.svg";
      logo-always-visible = true;
    };

    "org/gnome/desktop/screensaver" = {
      lock-enabled = false;
      lock-delay   = lib.gvariant.mkUint32 0;
    };

    "org/gnome/session" = {
      idle-delay = lib.gvariant.mkUint32 300;  # 5 min inactivity
    };

    "org/gnome/desktop/app-folders" = {
      folder-children = [ "Games" "Game Utilities" "Office" "Utilities" "System" ];
    };

    "org/gnome/desktop/app-folders/folders/Games" = {
      name = "Games";
      apps = [
        "org.prismlauncher.PrismLauncher.desktop"
        "net.lutris.Lutris.desktop"
        "steam.desktop"
      ];
    };

    "org/gnome/desktop/app-folders/folders/Game Utilities" = {
      name = "Game Utilities";
      apps = [
        "com.vysp3r.ProtonPlus.desktop"
        "protontricks.desktop"
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
  # ── State version ──────────────────────────────────────────────────────────
  # Do NOT change after first activation — tracks the HM release at initial install.
  home.stateVersion = "24.05";
}
