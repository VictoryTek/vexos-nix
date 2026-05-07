# home-server.nix
# Home Manager configuration for user "nimda" — GUI Server role.
# Shell environment, theming, and GNOME settings for a server with a GNOME desktop.
# No gaming, no dev-language tooling. Focus: sysadmin utilities and remote management.
{ config, pkgs, lib, inputs, ... }:
{
  imports = [ ./home/bash-common.nix ./home/gnome-common.nix ];

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
    # NOTE: just is installed system-wide via modules/packages-common.nix.

    # System utilities
    fastfetch
    # NOTE: gparted is installed system-wide via modules/packages-desktop.nix.
    # NOTE: btop and inxi are installed system-wide via modules/packages-common.nix.

    # NOTE: brave is installed as a Nix package (see modules/packages-common.nix).
  ];

  # ── Starship prompt ────────────────────────────────────────────────────────
  programs.starship = {
    enable = true;
    enableBashIntegration = true;
  };

  xdg.configFile."starship.toml".source = ./files/starship.toml;

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
  home.file."scripts/create-zfs-pool.sh".source = ./scripts/create-zfs-pool.sh;
  home.file."template/server-services.nix".source = ./template/server-services.nix;

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
  home.file."Pictures/Wallpapers/vex-bb-light.jxl".source = ./wallpapers/server/vex-bb-light.jxl;
  home.file."Pictures/Wallpapers/vex-bb-dark.jxl".source  = ./wallpapers/server/vex-bb-dark.jxl;

  # ── GNOME dconf defaults ─────────────────────────────────────────────────
  # All dconf keys are set via the system dconf database in modules/gnome.nix
  # and modules/gnome-server.nix.  The system-db provides defaults; user
  # changes in GNOME Settings survive rebuilds because the user-db has higher
  # priority.

  # ── First-run app-folder layout ───────────────────────────────────────────
  # See comment in home-htpc.nix for rationale.
  systemd.user.services.vexos-init-app-folders = {
    Unit = {
      Description = "VexOS: initialise GNOME app folders (once)";
      After       = [ "graphical-session.target" ];
      PartOf      = [ "graphical-session.target" ];
    };
    Service = {
      Type            = "oneshot";
      RemainAfterExit = true;
      ExecStart       = toString (pkgs.writeShellScript "vexos-init-app-folders-server" ''
        STAMP="$HOME/.local/share/vexos/.dconf-app-folders-initialized"
        [ -f "$STAMP" ] && exit 0

        D="${pkgs.dconf}/bin/dconf"

        $D write /org/gnome/desktop/app-folders/folder-children \
          "['Office', 'Utilities', 'System']"

        $D write /org/gnome/desktop/app-folders/folders/Office/name   "'Office'"
        $D write /org/gnome/desktop/app-folders/folders/Office/apps \
          "['org.gnome.TextEditor.desktop']"

        $D write /org/gnome/desktop/app-folders/folders/Utilities/name "'Utilities'"
        $D write /org/gnome/desktop/app-folders/folders/Utilities/apps \
          "['com.mattjakeman.ExtensionManager.desktop', 'it.mijorus.gearlever.desktop', 'org.gnome.tweaks.desktop', 'io.github.flattool.Warehouse.desktop', 'io.missioncenter.MissionCenter.desktop', 'com.github.tchx84.Flatseal.desktop', 'org.gnome.World.PikaBackup.desktop']"

        $D write /org/gnome/desktop/app-folders/folders/System/name    "'System'"
        $D write /org/gnome/desktop/app-folders/folders/System/apps \
          "['org.pulseaudio.pavucontrol.desktop', 'io.missioncenter.MissionCenter.desktop', 'org.gnome.Settings.desktop', 'org.gnome.seahorse.Application.desktop', 'nixos-manual.desktop', 'cups.desktop', 'gparted.desktop', 'blueman-manager.desktop', 'btop.desktop', 'ca.desrt.dconf-editor.desktop', 'org.gnome.baobab.desktop', 'org.gnome.DiskUtility.desktop', 'org.gnome.font-viewer.desktop', 'org.gnome.Logs.desktop', 'btrfs-assistant.desktop', 'org.gnome.SystemMonitor.desktop']"

        mkdir -p "$HOME/.local/share/vexos"
        touch "$STAMP"
      '');
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  # ── First-run extension enablement ────────────────────────────────────────
  # GNOME Shell initialises org/gnome/shell/enabled-extensions to [] on first
  # session start, shadowing the system dconf defaults (same issue as
  # folder-children — see vexos-init-app-folders comment above).
  # A stamp file prevents re-running, so manual changes survive future rebuilds.
  # To reset: delete ~/.local/share/vexos/.dconf-extensions-initialized
  systemd.user.services.vexos-init-extensions = {
    Unit = {
      Description = "VexOS: initialise GNOME enabled-extensions (once)";
      After       = [ "graphical-session.target" ];
      PartOf      = [ "graphical-session.target" ];
    };
    Service = {
      Type            = "oneshot";
      RemainAfterExit = true;
      ExecStart       = toString (pkgs.writeShellScript "vexos-init-extensions-server" ''
        STAMP="$HOME/.local/share/vexos/.dconf-extensions-initialized"
        [ -f "$STAMP" ] && exit 0

        D="${pkgs.dconf}/bin/dconf"

        $D write /org/gnome/shell/enabled-extensions \
          "['appindicatorsupport@rgcjonas.gmail.com', 'dash-to-dock@micxgx.gmail.com', 'AlphabeticalAppGrid@stuarthayhurst', 'gnome-ui-tune@itstime.tech', 'nothing-to-say@extensions.gnome.wouter.bolsterl.ee', 'steal-my-focus-window@steal-my-focus-window', 'tailscale-status@maxgallup.github.com', 'caffeine@patapon.info', 'restartto@tiagoporsch.github.io', 'blur-my-shell@aunetx', 'background-logo@fedorahosted.org', 'tiling-assistant@leleat-on-github']"

        mkdir -p "$HOME/.local/share/vexos"
        touch "$STAMP"
      '');
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  home.stateVersion = "24.05";
}
