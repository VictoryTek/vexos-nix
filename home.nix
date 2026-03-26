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

  # ── Hidden app grid entries ────────────────────────────────────────────────
  # These packages cannot be safely removed (they are required dependencies),
  # so their .desktop files are masked to keep them out of the app grid.
  xdg.desktopEntries."org.gnome.Extensions" = {
    name      = "Extensions";
    noDisplay = true;
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
  # JXL format requires a gdk-pixbuf loader; GNOME on NixOS may need jxl-pixbuf-loader
  # added to environment.systemPackages in modules/desktop.nix if wallpapers don't appear.
  home.file."Pictures/Wallpapers/vex-bb-light.jxl".source = ./wallpapers/vex-bb-light.jxl;
  home.file."Pictures/Wallpapers/vex-bb-dark.jxl".source  = ./wallpapers/vex-bb-dark.jxl;
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
        pkgs.unstable.gnomeExtensions.restart-to.extensionUuid
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

    "org/gnome/desktop/screensaver" = {
      lock-enabled = true;
      lock-delay   = lib.gvariant.mkUint32 0;  # lock immediately
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
  # ── State version ──────────────────────────────────────────────────────────
  # Do NOT change after first activation — tracks the HM release at initial install.
  home.stateVersion = "24.05";
}
