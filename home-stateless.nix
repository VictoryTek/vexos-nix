# home-stateless.nix
# Home Manager configuration for user "nimda" — Stateless role.
# Same as desktop minus gaming app folders and dev-only packages (no development.nix on stateless).
{ config, pkgs, lib, inputs, ... }:
{
  imports = [
    ./home/gnome-common.nix
  ];

  home.username    = "nimda";
  home.homeDirectory = "/home/nimda";

  # ── User packages ──────────────────────────────────────────────────────────
  home.packages = with pkgs; [
    # Privacy browser
    tor-browser  # Routes traffic through the Tor network (Tails-like stateless role)

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

  # ── PhotoGIMP orphan cleanup ───────────────────────────────────────────────
  # Removes any leftover PhotoGIMP desktop entry or icon overrides from a
  # previous desktop-role Home Manager generation or manual PhotoGIMP install.
  # The photogimp.nix module is never imported on stateless; all its cleanup
  # activations are gated behind photogimp.enable = true and never fire here.
  # This activation removes BOTH real files AND symlinks (unlike the cleanup in
  # photogimp.nix which only removes real files).
  home.activation.cleanupPhotogimpOrphans =
    lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
      DESKTOP_FILE="$HOME/.local/share/applications/org.gimp.GIMP.desktop"
      if [ -e "$DESKTOP_FILE" ] || [ -L "$DESKTOP_FILE" ]; then
        $VERBOSE_ECHO "Stateless: removing orphaned PhotoGIMP desktop entry"
        $DRY_RUN_CMD rm -f "$DESKTOP_FILE"
      fi

      for size in 16x16 32x32 48x48 64x64 128x128 256x256 512x512; do
        ICON_FILE="$HOME/.local/share/icons/hicolor/$size/apps/photogimp.png"
        if [ -e "$ICON_FILE" ] || [ -L "$ICON_FILE" ]; then
          $VERBOSE_ECHO "Stateless: removing orphaned PhotoGIMP icon $size"
          $DRY_RUN_CMD rm -f "$ICON_FILE"
        fi
      done

      for stray in \
        "$HOME/.local/share/icons/hicolor/photogimp.png" \
        "$HOME/.local/share/icons/hicolor/256x256/256x256.png"; do
        if [ -e "$stray" ] || [ -L "$stray" ]; then
          $VERBOSE_ECHO "Stateless: removing stray PhotoGIMP file $stray"
          $DRY_RUN_CMD rm -f "$stray"
        fi
      done

      APP_DIR="$HOME/.local/share/applications"
      ICON_DIR="$HOME/.local/share/icons/hicolor"
      if [ -d "$APP_DIR" ]; then
        $VERBOSE_ECHO "Stateless: refreshing desktop database after PhotoGIMP cleanup"
        $DRY_RUN_CMD ${pkgs.desktop-file-utils}/bin/update-desktop-database "$APP_DIR"
      fi
      if [ -d "$ICON_DIR" ]; then
        $VERBOSE_ECHO "Stateless: refreshing icon cache after PhotoGIMP cleanup"
        $DRY_RUN_CMD ${pkgs.gtk3}/bin/gtk-update-icon-cache -f -t "$ICON_DIR"
      fi
    '';

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
        "torbrowser.desktop"
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

    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
      accent-color = "teal";
    };
  };

  home.stateVersion = "24.05";
}
