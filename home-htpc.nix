# home-htpc.nix
# Home Manager configuration for user "nimda" — HTPC role.
# Manages HTPC-specific wallpapers, GNOME dconf wallpaper settings, and media-centre defaults.
{ config, pkgs, lib, inputs, ... }:
{
  imports = [ ./home/bash-common.nix ./home/gnome-common.nix ];

  home.username    = "nimda";
  home.homeDirectory = "/home/nimda";

  # ── Starship prompt ────────────────────────────────────────────────────────
  programs.starship = {
    enable = true;
    enableBashIntegration = true;
  };

  xdg.configFile."starship.toml".source = ./files/starship.toml;

  # ── Wallpapers ─────────────────────────────────────────────────────────────
  # Copied from the repo into ~/Pictures/Wallpapers/ at each activation.
  home.file."Pictures/Wallpapers/vex-bb-light.jxl".source = ./wallpapers/htpc/vex-bb-light.jxl;
  home.file."Pictures/Wallpapers/vex-bb-dark.jxl".source  = ./wallpapers/htpc/vex-bb-dark.jxl;

  # ── GNOME dconf defaults ─────────────────────────────────────────────────
  # All dconf keys are set via the system dconf database in modules/gnome.nix
  # and modules/gnome-htpc.nix.  The system-db provides defaults; user changes
  # in GNOME Settings survive rebuilds because the user-db has higher priority.

  # ── First-run app-folder layout ───────────────────────────────────────────
  # GNOME initialises org/gnome/desktop/app-folders/folder-children to [] on
  # first session start, which shadows the system dconf defaults.  This
  # one-shot user service writes the folder layout once on the first graphical
  # login (when dbus is available).  A stamp file prevents it running again,
  # so manual folder changes survive all future rebuilds.
  # To reset: delete the stamp or run `just reset-defaults`.
  systemd.user.services.vexos-init-app-folders = {
    Unit = {
      Description = "VexOS: initialise GNOME app folders (once)";
      After       = [ "graphical-session.target" ];
      PartOf      = [ "graphical-session.target" ];
    };
    Service = {
      Type            = "oneshot";
      RemainAfterExit = true;
      ExecStart       = toString (pkgs.writeShellScript "vexos-init-app-folders-htpc" ''
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
          "['org.pulseaudio.pavucontrol.desktop', 'rog-control-center.desktop', 'io.missioncenter.MissionCenter.desktop', 'org.gnome.Settings.desktop', 'org.gnome.seahorse.Application.desktop', 'nixos-manual.desktop', 'cups.desktop', 'gparted.desktop', 'blueman-manager.desktop', 'btop.desktop', 'ca.desrt.dconf-editor.desktop', 'org.gnome.baobab.desktop', 'org.gnome.DiskUtility.desktop', 'org.gnome.font-viewer.desktop', 'org.gnome.Logs.desktop', 'btrfs-assistant.desktop', 'org.gnome.SystemMonitor.desktop']"

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
      ExecStart       = toString (pkgs.writeShellScript "vexos-init-extensions-htpc" ''
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

  # ── Hidden app grid entries ────────────────────────────────────────────────
  # These packages cannot be safely removed (they are required dependencies),
  # so their .desktop files are masked to keep them out of the app grid.
  xdg.desktopEntries."org.gnome.Extensions" = {
    name      = "Extensions";
    noDisplay = true;
    settings.Hidden = "true";
  };
  # ── Justfile ───────────────────────────────────────────────────────────────
  # Deploy the repo's justfile to ~/justfile so 'just' works from home dir.
  home.file."justfile".source = ./justfile;

  home.stateVersion = "24.05";
}
