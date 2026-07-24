# home-desktop.nix
# Home Manager configuration for the primary user (vexos.user.name).
# Manages user-level packages, shell, GNOME dconf settings, GTK theming, and cursors.
# Consumed by mkHomeManagerModule in flake.nix via home-manager.users.${osConfig.vexos.user.name}.
{ config, pkgs, lib, inputs, osConfig, ... }:
{
  imports = [
    ./home/bash-common.nix
    ./home/photogimp.nix
    ./home/gnome-common.nix
    ./home/gnome-common-browser.nix
  ];

  photogimp.enable = true;

  home.username    = osConfig.vexos.user.name;
  home.homeDirectory = "/home/${osConfig.vexos.user.name}";

  # ── User packages ──────────────────────────────────────────────────────────
  home.packages = with pkgs; [
    # Development tools
    # NOTE: VS Code (programs.vscode, below) is currently disabled.
    rustup
    unstable.nodejs  # latest LTS (nodejs_25 removed — EOL 2026-06-01)

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

    # NOTE: pavucontrol and protonplus are installed via Flatpak (see modules/flatpak.nix).
    # brave is installed as a Nix package (see modules/packages-common.nix).
  ];

  # ── Starship prompt ────────────────────────────────────────────────────────
  programs.starship = {
    enable = true;
    enableBashIntegration = true;
  };

  xdg.configFile."starship.toml".source = ./files/starship.toml;

  # ── VS Code (package + settings managed declaratively) ───────────────────
  # Installs vscode-fhs into the user profile and deploys settings to
  # ~/.config/Code/User/profiles/default/settings.json on every activation.
  # Temporarily disabled — re-enable by uncommenting this block.
  # programs.vscode = {
  #   enable  = true;
  #   package = pkgs.unstable.vscode-fhs;
  #   profiles.default.userSettings = {
  #     "files.exclude" = {
  #       "**/.direnv" = true;
  #       "**/result"  = true;
  #     };
  #     "files.watcherExclude" = {
  #       "**/.direnv/**"      = true;
  #       "**/.git/**"         = true;
  #       "**/node_modules/**" = true;
  #       "**/result/**"       = true;
  #       "/nix/store/**"      = true;
  #     };
  #     "rust-analyzer.cargo.buildScripts.enable" = false;
  #     "rust-analyzer.check.command" = "check";
  #     "rust-analyzer.server.extraEnv" = {
  #       "RA_MEMORY_LIMIT" = "4096";
  #     };
  #     "workbench.enableExperiments" = false;
  #     "claudeCode.preferredLocation" = "panel";
  #   };
  # };

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

  # ── Desktop entry overrides ───────────────────────────────────────────────
  # gparted: nixpkgs 25.05 ships its .desktop file with NoDisplay=true.
  # Override at the user level to restore visibility in the app grid.
  xdg.desktopEntries."gparted" = {
    name       = "GParted";
    exec       = "gparted %f";
    icon       = "gparted";
    comment    = "Create, reorganize, and delete disk partitions";
    categories = [ "System" ];
  };

  # ── Session environment variables ─────────────────────────────────────────
  # NIXOS_OZONE_WL: forces Electron apps (VS Code, etc.) to use the Wayland backend.
  # MOZ_ENABLE_WAYLAND: forces Firefox/Zen to use the Wayland backend.
  # QT_QPA_PLATFORM: ensures Qt apps prefer Wayland with XCB as fallback.
  home.sessionVariables = {
    NIXOS_OZONE_WL     = "1";
    MOZ_ENABLE_WAYLAND = "1";
    QT_QPA_PLATFORM    = "wayland;xcb";
    # Cap Electron / Node heap — prevents VS Code OOM on 32 GB systems.
    # NOTE: bare --max-old-space-size is a V8/Node flag, not a Chromium switch;
    # it must be inside --js-flags to reach the renderer V8 heap.  NODE_OPTIONS
    # caps each extension-host (NodeService) process independently.
    ELECTRON_EXTRA_LAUNCH_ARGS = "--js-flags=--max-old-space-size=4096";
    NODE_OPTIONS               = "--max-old-space-size=4096";
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

  # ── One-time dock migration: brave-browser → brave-origin ────────────────
  # The user dconf database overrides system-level dconf defaults. If a prior
  # rebuild wrote brave-browser.desktop into the user dconf via dconf.settings,
  # the system default of brave-origin.desktop is invisible until the user key
  # is updated. This service runs once (stamp file) to perform that replacement.
  systemd.user.services.vexos-migrate-dock-brave-origin = {
    Unit = {
      Description = "VexOS: migrate dock from brave-browser to brave-origin (once)";
      After       = [ "graphical-session.target" ];
      PartOf      = [ "graphical-session.target" ];
    };
    Service = {
      Type            = "oneshot";
      RemainAfterExit = true;
      ExecStart       = toString (pkgs.writeShellScript "vexos-migrate-dock-brave-origin" ''
        STAMP="$HOME/.local/share/vexos/.dock-brave-origin-migration-v1"
        [ -f "$STAMP" ] && exit 0

        CURRENT=$(${pkgs.dconf}/bin/dconf read /org/gnome/shell/favorite-apps)
        if echo "$CURRENT" | grep -q "brave-browser\.desktop"; then
          UPDATED=$(echo "$CURRENT" | ${pkgs.gnused}/bin/sed \
            "s/brave-browser\.desktop/brave-origin.desktop/g")
          ${pkgs.dconf}/bin/dconf write /org/gnome/shell/favorite-apps "$UPDATED"
        fi

        mkdir -p "$HOME/.local/share/vexos"
        touch "$STAMP"
      '');
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

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
      ExecStart       = toString (pkgs.writeShellScript "vexos-init-app-folders-desktop" ''
        STAMP="$HOME/.local/share/vexos/.dconf-app-folders-initialized-v3"
        [ -f "$STAMP" ] && exit 0

        D="${pkgs.dconf}/bin/dconf"

        $D write /org/gnome/desktop/app-folders/folder-children \
          "['Games', 'Game Utilities', 'Office', '3D', 'Utilities', 'System']"

        $D write /org/gnome/desktop/app-folders/folders/Games/name  "'Games'"
        $D write /org/gnome/desktop/app-folders/folders/Games/apps \
          "['org.prismlauncher.PrismLauncher.desktop', 'net.lutris.Lutris.desktop', 'steam.desktop', 'com.hypixel.HytaleLauncher.desktop', 'Ryujinx.desktop', 'com.libretro.RetroArch.desktop']"

        $D write /org/gnome/desktop/app-folders/folders/"Game Utilities"/name "'Game Utilities'"
        $D write /org/gnome/desktop/app-folders/folders/"Game Utilities"/apps \
          "['com.vysp3r.ProtonPlus.desktop', 'protontricks.desktop', 'dev.vencord.Vesktop.desktop', 'com.discordapp.Discord.desktop']"

        $D write /org/gnome/desktop/app-folders/folders/Office/name   "'Office'"
        $D write /org/gnome/desktop/app-folders/folders/Office/apps \
          "['org.onlyoffice.desktopeditors.desktop', 'org.gnome.TextEditor.desktop', 'org.gnome.Papers.desktop', 'net.cozic.joplin_desktop.desktop']"

        $D write /org/gnome/desktop/app-folders/folders/"3D"/name "'3D'"
        $D write /org/gnome/desktop/app-folders/folders/"3D"/apps \
          "['org.blender.Blender.desktop', 'com.orcaslicer.OrcaSlicer.desktop']"

        $D write /org/gnome/desktop/app-folders/folders/Utilities/name "'Utilities'"
        $D write /org/gnome/desktop/app-folders/folders/Utilities/apps \
          "['com.mattjakeman.ExtensionManager.desktop', 'it.mijorus.gearlever.desktop', 'org.gnome.tweaks.desktop', 'io.github.flattool.Warehouse.desktop', 'io.missioncenter.MissionCenter.desktop', 'com.github.tchx84.Flatseal.desktop', 'org.gnome.World.PikaBackup.desktop', 'nvidia-settings.desktop', 'LocalSend.desktop']"

        $D write /org/gnome/desktop/app-folders/folders/System/name    "'System'"
        $D write /org/gnome/desktop/app-folders/folders/System/apps \
          "['org.pulseaudio.pavucontrol.desktop', 'rog-control-center.desktop', 'io.missioncenter.MissionCenter.desktop', 'org.gnome.Settings.desktop', 'org.gnome.seahorse.Application.desktop', 'nixos-manual.desktop', 'cups.desktop', 'gparted.desktop', 'blueman-manager.desktop', 'btop.desktop', 'ca.desrt.dconf-editor.desktop', 'org.gnome.baobab.desktop', 'org.gnome.DiskUtility.desktop', 'org.gnome.font-viewer.desktop', 'org.gnome.Logs.desktop', 'btrfs-assistant.desktop', 'org.gnome.SystemMonitor.desktop', 'com.system76.Popsicle.desktop']"

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
      ExecStart       = toString (pkgs.writeShellScript "vexos-init-extensions-desktop" ''
        STAMP="$HOME/.local/share/vexos/.dconf-extensions-initialized-v3"
        [ -f "$STAMP" ] && exit 0

        D="${pkgs.dconf}/bin/dconf"

        $D write /org/gnome/shell/disabled-extensions "[]"

        $D write /org/gnome/shell/enabled-extensions \
          "['appindicatorsupport@rgcjonas.gmail.com', 'dash-to-dock@micxgx.gmail.com', 'AlphabeticalAppGrid@stuarthayhurst', 'gnome-ui-tune@itstime.tech', 'nothing-to-say@extensions.gnome.wouter.bolsterl.ee', 'steal-my-focus-window@steal-my-focus-window', 'tailscale-status@maxgallup.github.com', 'caffeine@patapon.info', 'blur-my-shell@aunetx', 'background-logo@fedorahosted.org', 'tiling-assistant@leleat-on-github', 'gamemodeshellextension@trsnaqe.com']"

        # Clear the user-dconf nothing-to-say keybinding so it does not
        # conflict with the gsd-media-keys binding that calls wpctl directly.
        $D write /org/gnome/shell/extensions/nothing-to-say/keybinding-toggle-mute "[]"

        mkdir -p "$HOME/.local/share/vexos"
        touch "$STAMP"
      '');
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  # ── State version ──────────────────────────────────────────────────────────
  # Do NOT change after first activation — tracks the HM release at initial install.
  home.stateVersion = "24.05";
}
