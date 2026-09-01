# home/dank-material-shell.nix
# DankMaterialShell (DMS) desktop shell (user layer), plus the polkit agent and
# removable-media automounter that GNOME Shell supplied implicitly and DMS does
# not replace.
# Active only when vexos.desktop.environment == "hyprland" — imported
# unconditionally by home-desktop.nix and gated internally, matching the shape
# of home/gnome-common.nix and the system-side DE modules.
#
# Why the Home Manager module and not the NixOS one: upstream ships both under
# the option path `programs.dank-material-shell`, but only the home module
# carries `settings` / `clipboardSettings` / `session` (the JSON surface the
# later customisation phase needs) and a systemd user service with
# restartIfChanged triggers. The NixOS module would install the shell binary
# system-wide with no settings surface — see flake.nix dmsBase, which imports it
# for its option declarations only and never sets `enable`.
{ config, pkgs, lib, inputs, osConfig, ... }:
{
  # Imports cannot be conditional — they are resolved before option values
  # exist — so this sits outside the mkIf below. The upstream module is inert
  # until programs.dank-material-shell.enable is set, so non-Hyprland desktops
  # are unaffected by its presence.
  imports = [ inputs.dms.homeModules.dank-material-shell ];

  config = lib.mkIf (osConfig.vexos.desktop.environment == "hyprland") {
    # ── DankMaterialShell ───────────────────────────────────────────────────
    # systemd.enable binds dms.service to config.wayland.systemd.target, which
    # resolves to graphical-session.target — activated by UWSM (see the comment
    # in modules/hyprland-desktop.nix; without UWSM this never starts).
    #
    # `clipboardSettings` is deliberately left unset — stock clipboard
    # behaviour. `settings` and `session` below port the subset of GNOME's
    # dconf defaults (modules/gnome.nix, modules/gnome-desktop.nix) that have
    # a real DMS equivalent; see
    # .github/docs/subagent_docs/hyprland_dms_gnome_parity_spec.md for the
    # full key-by-key mapping and what was deliberately skipped. Bar/widget
    # layout and plugins remain a later customisation phase.
    programs.dank-material-shell = {
      enable                 = true;
      systemd.enable         = true;
      quickshell.package     = pkgs.quickshell;   # 0.3.0 in nixos-26.05
      dgop.package           = pkgs.dgop;         # set explicitly — no module default
      enableSystemMonitoring = true;              # dgop  — system/process widgets
      enableCalendarEvents   = true;              # khal  — calendar events
      enableDynamicTheming   = true;              # matugen — Material-You theming
      enableAudioWavelength  = true;              # cava  — audio visualiser
      enableVPN              = true;              # networkmanager (enabled system-side)

      # ── settings.json — persistent preferences ─────────────────────────────
      settings = {
        # GNOME: org/gnome/desktop/interface clock-format=12h (default here is "auto")
        clockFormat = "12h";

        # GNOME: org/gnome/shell/extensions/dash-to-dock (position=LEFT, autohide, intellihide)
        showDock         = true;
        dockPosition      = 2;      # SettingsData.Position.Left (Top=0, Bottom=1, Left=2, Right=3)
        dockAutoHide      = true;
        dockSmartAutoHide = true;   # closest DMS equivalent to GNOME's intellihide

        # VexOS Neo-Cyberpunk theme — hand-built from the wallpaper's own
        # extracted colors (see
        # .github/docs/subagent_docs/hyprland_neo_cyberpunk_rice_spec.md),
        # deployed below via xdg.configFile. enableDynamicTheming above only
        # makes matugen available for per-app template export — it does not
        # override this explicit theme selection.
        currentThemeName = "custom";
        customThemeFile  = "${config.home.homeDirectory}/.config/DankMaterialShell/themes/vexos-neo-cyberpunk.json";
      };

      # ── session.json — wallpaper, mode, pinned apps ────────────────────────
      session = {
        # GNOME: org/gnome/desktop/interface color-scheme=prefer-dark
        isLightMode = false;

        # GNOME: org/gnome/desktop/background picture-uri(-dark) — same files
        # home-desktop.nix already deploys to ~/Pictures/Wallpapers/.
        perModeWallpaper   = true;
        wallpaperPath      = "${config.home.homeDirectory}/Pictures/Wallpapers/vex-bb-dark.jxl";
        wallpaperPathLight = "${config.home.homeDirectory}/Pictures/Wallpapers/vex-bb-light.jxl";
        wallpaperPathDark  = "${config.home.homeDirectory}/Pictures/Wallpapers/vex-bb-dark.jxl";

        # GNOME: org/gnome/shell favorite-apps — same app set as
        # modules/gnome-desktop.nix, as bare desktop-file IDs (no .desktop
        # suffix, per DMS's DesktopEntries/Paths.moddedAppId convention).
        pinnedApps = [
          "brave-origin"
          "app.zen_browser.zen"
          "org.gnome.Nautilus"
          "com.mitchellh.ghostty"
          "io.github.up"
          "org.gnome.Boxes"
          "codium"
        ];
        barPinnedApps = [
          "brave-origin"
          "app.zen_browser.zen"
          "org.gnome.Nautilus"
          "com.mitchellh.ghostty"
          "io.github.up"
          "org.gnome.Boxes"
          "codium"
        ];
      };

      # ── Plugins ─────────────────────────────────────────────────────────────
      # DMS has its own native plugin system (unrelated to, and incompatible
      # with, Omarchy's own plugin system — different shell, different
      # manifest format, no interop). Community plugins:
      # https://plugins.danklinux.com/ · dev docs: search the dms flake input
      # for .agents/skills/dms-plugin-dev/SKILL.md
      #
      # Uncomment and edit to add one (pin a rev + sha256, don't float):
      # plugins.SomePlugin.src = pkgs.fetchFromGitHub {
      #   owner  = "someone";
      #   repo   = "SomePlugin";
      #   rev    = "...";
      #   sha256 = "...";
      # };
    };

    # ── VexOS Neo-Cyberpunk theme + terminal palette ────────────────────────
    # Deploys the custom DMS theme referenced by settings.customThemeFile
    # above, plus a matching Ghostty color scheme (Hyprland role only — the
    # GNOME/COSMIC roles' Ghostty, wherever installed, is untouched).
    xdg.configFile."DankMaterialShell/themes/vexos-neo-cyberpunk.json".source =
      ../files/dms/vexos-neo-cyberpunk.json;
    xdg.configFile."ghostty/config".source = ../files/ghostty/config;

    # ── Polkit authentication agent ─────────────────────────────────────────
    # GNOME Shell provided this; DMS does not. Without it, any action needing
    # authentication (mounting a system disk, some Flatpak operations) silently
    # fails with no prompt.
    services.hyprpolkitagent.enable = true;

    # ── Removable-media automount ───────────────────────────────────────────
    # GNOME Shell auto-mounted USB drives; DMS does not. Requires
    # services.udisks2 system-side (set in modules/hyprland-desktop.nix).
    services.udiskie = {
      enable    = true;
      automount = true;
      tray      = "auto";
    };

    # ── Mic mute on login ─────────────────────────────────────────────────────
    # GNOME equivalent: modules/gnome-desktop.nix mute-mic-on-login. Ported
    # verbatim (wpctl, not `dms ipc call mic mute`) so it works even before
    # dms.service has finished starting.
    systemd.user.services.mute-mic-on-login = {
      Unit = {
        Description = "Mute microphone at graphical session start";
        After       = [ "graphical-session.target" ];
        PartOf      = [ "graphical-session.target" ];
      };
      Service = {
        Type      = "oneshot";
        ExecStart = "${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SOURCE@ 1";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    # ── Seed a minimal hyprland.conf, once ──────────────────────────────────
    # Hyprland is otherwise unconfigured (autogenerated default). DMS's launcher,
    # clipboard, notification center, control center and lock are all `dms ipc
    # call` targets with no default bar button, so an unconfigured Hyprland gives
    # a shell you cannot open anything from. This copies the repo's minimal
    # DMS-focused config into place ONLY if the user has none yet; after first
    # boot the file is user-owned and nixos-rebuild never touches it again.
    # Same one-shot pattern as the vexos-init-* services in home-desktop.nix.
    home.activation.seedHyprlandConf =
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        target="$HOME/.config/hypr/hyprland.conf"
        if [ ! -e "$target" ]; then
          run mkdir -p "$HOME/.config/hypr"
          run cp ${../files/hypr/hyprland.conf} "$target"
          run chmod u+w "$target"
        fi
      '';
  };
}
