# modules/htpc-theater.nix
# HTPC "theater mode": VexTheater (github:VictoryTek/VexTheater), a full-screen,
# remote-friendly tile launcher that runs inside the normal GNOME session as a
# systemd user service. GNOME is the only session: GDM logs in automatically
# (modules/gnome.nix) and the launcher starts on top of it.
#
#   - Theater mode is the launcher full screen; desktop mode is the launcher hidden
#     (the Desktop Mode tile), which shows the plain GNOME desktop behind it.
#   - The home key (a GNOME custom shortcut running `vextheater --home`) closes the
#     running app and brings the launcher back, from an app or from desktop mode.
#     The CEC remote and the gamepad Guide button press the same key through ydotool.
#   - If VexTheater fails to start the user is simply in GNOME: the service is a
#     separate unit, so nothing here can leave a black screen. A crash loop is cut
#     off after five failures in a minute, and "Theater Mode" in the app grid starts
#     the launcher by hand.
#
# The tiles below are turned into VexTheater's /etc/vextheater/config.json; its
# schema (README.md and src/config.rs in the VexTheater repo) is the contract
# between the two repositories. VexTheater's NixOS module comes in through
# flake.nix (vexTheaterModule, htpc role): `imports` cannot reference `inputs`.
#
# Imported only by configuration-htpc.nix.
{ config, pkgs, lib, ... }:
let
  cfg = config.vexos.htpc.theater;
  vt  = config.programs.vextheater;

  kora  = "${pkgs.kora-icon-theme}/share/icons/kora/apps/scalable";
  brave = lib.getExe pkgs.vexos.brave-origin;

  # Same artwork as the HTPC desktop wallpaper. GTK's image loaders may lack
  # JPEG XL, so convert to JPEG at build time.
  wallpaper = pkgs.runCommand "vexos-htpc-theater-wallpaper.jpg" { nativeBuildInputs = [ pkgs.libjxl ]; } ''
    djxl ${../wallpapers/htpc/vex-bb-dark.jxl} $out --jpeg_quality=92
  '';

  # Linux evdev key codes for ydotool (CEC and gamepad Guide mapping).
  # Its attribute names are also the allowed homeKey values: GNOME accelerator
  # names, which is what the custom shortcut below takes.
  keyCodes = {
    F1 = 59; F2 = 60; F3 = 61; F4 = 62; F5 = 63; F6 = 64;
    F7 = 65; F8 = 66; F9 = 67; F10 = 68; F11 = 87; F12 = 88;
    Home = 102;
  };
  homeKeyCode = toString keyCodes.${cfg.homeKey};

  # Smart-TV user agent from the Flex Launcher docs; makes youtube.com/tv
  # serve its TV interface.
  smartTvUserAgent = "Mozilla/5.0 (Linux; Tizen 2.3; SmartHub; SMART-TV; SmartTV; U; Maple2012) AppleWebKit/538.1+ (KHTML, like Gecko) TV Safari/538.1+";

  slug = name: lib.toLower (lib.strings.sanitizeDerivationName name);

  # Brave rather than nixpkgs chromium: chromium ships without Widevine, so
  # DRM streaming sites would not play. Each web app gets its own profile so
  # logins persist per site and a still-running instance can never swallow a
  # different --user-agent. On first launch the profile is pre-seeded with
  # Brave's Widevine opt-in so DRM content works without a settings detour.
  mkWebApp = { name, icon, url, description ? null, tvUserAgent ? false }: {
    inherit name icon description;
    command = toString (pkgs.writeShellScript "vexos-htpc-webapp-${slug name}" ''
      dir="$HOME/.local/share/vexos-htpc/webapps/${slug name}"
      mkdir -p "$dir"
      [ -e "$dir/Local State" ] || printf '%s\n' '{"brave":{"widevine_opted_in":true}}' > "$dir/Local State"
      exec ${brave} --kiosk --app=${lib.escapeShellArg url} --user-data-dir="$dir" ${
        lib.optionalString tvUserAgent "--user-agent=${lib.escapeShellArg smartTvUserAgent}"}
    '');
  };

  # ── Tiles ────────────────────────────────────────────────────────────────
  # One tile = a name, an icon and exactly one action, as in VexTheater's schema.
  actionKeys = [ "command" "desktop" "flatpak" "submenu" "builtin" ];

  nullStr = lib.types.nullOr lib.types.str;

  tileType = lib.types.submodule {
    options = {
      name = lib.mkOption {
        type        = lib.types.str;
        description = "Tile title.";
      };
      icon = lib.mkOption {
        # A path (copied to the store) or an absolute path string is an image
        # file; any other string is an icon-theme name, e.g. "system-shutdown-symbolic".
        type        = lib.types.coercedTo lib.types.path (p: "${p}") lib.types.str;
        description = "Tile icon: an image file (SVG, or PNG/WebP with transparency) or an icon-theme name.";
      };
      description = lib.mkOption {
        type        = nullStr;
        default     = null;
        description = "One line shown under the title while the tile is selected.";
      };
      command = lib.mkOption {
        type        = nullStr;
        default     = null;
        description = "Shell command line, run through sh.";
      };
      desktop = lib.mkOption {
        type        = nullStr;
        default     = null;
        example     = "org.gnome.Nautilus.desktop";
        description = "Desktop file id of an installed application.";
      };
      flatpak = lib.mkOption {
        type        = nullStr;
        default     = null;
        example     = "io.freetubeapp.FreeTube";
        description = "Flatpak application id.";
      };
      submenu = lib.mkOption {
        type        = nullStr;
        default     = null;
        description = "Name of an entry in `submenus`, opened as its own row.";
      };
      builtin = lib.mkOption {
        type        = lib.types.nullOr (lib.types.enum [ "desktop-mode" "shutdown" "restart" ]);
        default     = null;
        description = "Launcher action: hide the launcher (desktop mode), or power off / restart.";
      };
    };
  };

  tileJson = tile: lib.filterAttrs (_: v: v != null)
    (lib.getAttrs ([ "name" "icon" "description" ] ++ actionKeys) tile);

  allTiles = cfg.apps ++ lib.concatLists (lib.attrValues cfg.submenus);
  tileActions = tile: lib.filter (key: tile.${key} != null) actionKeys;

  # Flex Launcher spelled special actions inside `command`; they are attributes now.
  legacyCommand = tile:
    tile.command != null
    && (lib.hasPrefix ":" tile.command || builtins.match "[^ ]*\\.desktop(;.*)?" tile.command != null);

  removedMessage = why: "${why} VexTheater (modules/htpc-theater.nix) replaced Flex Launcher.";
  removedStyling = path: lib.mkRemovedOptionModule
    ([ "vexos" "htpc" "theater" "theme" ] ++ path)
    (removedMessage "VexTheater styles itself with CSS, so the theme options no longer exist; remove this setting.");

  # Sends the home key through ydotoold (shared by CEC and gamepad Guide).
  pressHomeKey = "${lib.getExe pkgs.ydotool} key ${homeKeyCode}:1 ${homeKeyCode}:0";
  ydotoolEnv   = { YDOTOOL_SOCKET = config.environment.variables.YDOTOOL_SOCKET; };

  # HDMI-CEC remote → key presses. Reads cec-client traffic and acts on
  # "User Control Pressed" (opcode 0x44) frames.
  cecBridge = pkgs.writeShellScript "vexos-htpc-cec" ''
    press() { ${lib.getExe pkgs.ydotool} key "$1:1" "$1:0"; }
    # cec-client exits when stdin closes; keep it open.
    tail -f /dev/null | ${pkgs.libcec}/bin/cec-client -t p -o VexOS -d 8 |
      while IFS= read -r line; do
        case "$line" in
          *">> "?[0-9a-f]":44:00"*) press 28 ;;              # Select → Enter
          *">> "?[0-9a-f]":44:01"*) press 103 ;;             # Up
          *">> "?[0-9a-f]":44:02"*) press 108 ;;             # Down
          *">> "?[0-9a-f]":44:03"*) press 105 ;;             # Left
          *">> "?[0-9a-f]":44:04"*) press 106 ;;             # Right
          *">> "?[0-9a-f]":44:0d"*) press 14 ;;              # Exit/Back → Backspace
          *">> "?[0-9a-f]":44:09"*) press ${homeKeyCode} ;;  # Root menu/Home → homeKey
        esac
      done
  '';

  # Gamepad Guide button → home key, one instance per joystick event device.
  guideBridge = pkgs.writeShellScript "vexos-htpc-guide" ''
    ${pkgs.evtest}/bin/evtest "/dev/input/$1" |
      while IFS= read -r line; do
        case "$line" in
          *"(BTN_MODE), value 1"*) ${pressHomeKey} ;;
        esac
      done
  '';
in
{
  imports = [
    # Options that went away with Flex Launcher. Declared, not deleted, so a host's
    # /etc/nixos/features.nix that still sets one fails the build with this message
    # instead of an "option does not exist" error.
    (removedStyling [ "background" "mode" ])
    (removedStyling [ "background" "color" ])
    (removedStyling [ "background" "image" ])
    (removedStyling [ "background" "slideshowDirectory" ])
    (removedStyling [ "iconSize" ])
    (removedStyling [ "maxButtons" ])
    (removedStyling [ "titles" "font" ])
    (removedStyling [ "titles" "fontSize" ])
    (removedStyling [ "titles" "color" ])
    (removedStyling [ "highlight" "fillColor" ])
    (removedStyling [ "highlight" "fillOpacity" ])
    (removedStyling [ "highlight" "outlineSize" ])
    (removedStyling [ "highlight" "outlineColor" ])
    (removedStyling [ "highlight" "cornerRadius" ])
    (removedStyling [ "clock" "enable" ])
    (lib.mkRemovedOptionModule [ "vexos" "htpc" "theater" "defaultMode" ]
      (removedMessage "There is one session now: GNOME, with the launcher on top. A login always starts in theater mode, and a launcher that crashes in desktop mode restarts in desktop mode. To turn the launcher off entirely, set vexos.htpc.theater.enable = false."))
    (lib.mkRemovedOptionModule [ "vexos" "htpc" "theater" "user" ]
      (removedMessage "Auto-login goes through GDM for vexos.user.name (modules/gnome.nix)."))
    (lib.mkRemovedOptionModule [ "vexos" "htpc" "theater" "gamepad" "enable" ]
      (removedMessage "VexTheater has no gamepad navigation yet; remove this setting. vexos.htpc.theater.gamepad.homeButton still maps the Guide button to the home key."))
  ];

  options.vexos.htpc.theater = {
    enable = lib.mkEnableOption "HTPC theater mode (the VexTheater launcher on top of the GNOME session); false restores plain GNOME" // { default = true; };

    apps = lib.mkOption {
      type        = lib.types.listOf tileType;
      description = ''
        Main row tiles. The defaults are module definitions, so tiles you
        define are added (before Desktop Mode and Power); use lib.mkForce to
        replace the whole list.
      '';
    };

    submenus = lib.mkOption {
      type        = lib.types.attrsOf (lib.types.listOf tileType);
      description = "Submenus (name → tiles), opened by a tile with `submenu = \"<name>\"`.";
    };

    homeKey = lib.mkOption {
      type        = lib.types.enum (lib.attrNames keyCodes);
      default     = "F10";
      description = "Key that closes the running app and brings the launcher back (GNOME custom shortcut running `vextheater --home`).";
    };

    gamepad.homeButton = lib.mkEnableOption "mapping the gamepad Guide button to the home key (via ydotool)";

    cec.enable = lib.mkEnableOption "HDMI-CEC TV remote input via libcec (needs a CEC adapter such as a Pulse-Eight USB-CEC)";

    mkWebApp = lib.mkOption {
      type        = lib.types.raw;
      readOnly    = true;
      default     = mkWebApp;
      description = "Helper: mkWebApp { name; icon; url; description ? null; tvUserAgent ? false; } → a tile that opens url in a Brave kiosk window.";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      assertions = [
        {
          assertion = lib.all (t: lib.length (tileActions t) == 1) allTiles;
          message   = "vexos.htpc.theater: every tile needs exactly one of ${lib.concatStringsSep ", " actionKeys} (tiles breaking this: ${
            lib.concatStringsSep ", " (map (t: t.name) (lib.filter (t: lib.length (tileActions t) != 1) allTiles))}).";
        }
        {
          assertion = !(lib.any legacyCommand allTiles);
          message   = "vexos.htpc.theater: a tile's `command` starts with ':' or names a .desktop file, which was Flex Launcher syntax. Use `submenu = \"<name>\"`, `builtin = \"shutdown\"` (or \"restart\" / \"desktop-mode\"), or `desktop = \"<id>.desktop\"` instead.";
        }
        {
          assertion = lib.all (t: t.submenu == null || cfg.submenus ? ${t.submenu}) allTiles;
          message   = "vexos.htpc.theater: a tile opens a submenu that is not defined in vexos.htpc.theater.submenus.";
        }
      ];

      vexos.htpc.theater.apps = lib.mkMerge [ [
        (mkWebApp {
          name        = "YouTube";
          icon        = "${kora}/youtube.svg";
          description = "YouTube TV interface, full screen";
          url         = "https://www.youtube.com/tv";
          tvUserAgent = true;
        })
        {
          name        = "Plex";
          icon        = "${kora}/plex-htpc.svg";
          description = "Plex HTPC";
          command     = lib.getExe pkgs.plex-htpc;
        }
        (mkWebApp {
          name        = "Twitch";
          icon        = "${kora}/gnome-twitch.svg";
          description = "Live streams, full screen";
          url         = "https://www.twitch.tv";
        })
        {
          name        = "Browser";
          icon        = "${pkgs.vexos.brave-origin}/share/icons/hicolor/256x256/apps/brave-origin.png";
          description = "Brave, full screen";
          command     = "${brave} --start-fullscreen";
        }
      ] (lib.mkAfter [
        {
          name        = "Desktop Mode";
          icon        = "${kora}/preferences-desktop-display.svg";
          description = "Show the GNOME desktop";
          builtin     = "desktop-mode";
        }
        {
          name        = "Power";
          icon        = "system-shutdown-symbolic";
          description = "Shut down or restart";
          submenu     = "Power";
        }
      ]) ];

      # No Sleep tile: modules/system-nosleep.nix masks every sleep target.
      vexos.htpc.theater.submenus.Power = [
        { name = "Shutdown"; icon = "system-shutdown-symbolic"; description = "Turn the HTPC off";  builtin = "shutdown"; }
        { name = "Restart";  icon = "system-reboot-symbolic";   description = "Restart the HTPC";   builtin = "restart"; }
      ];

      environment.systemPackages = [ pkgs.plex-htpc ];

      # ── VexTheater ─────────────────────────────────────────────────────────
      # `autostart` runs it as a systemd user service in graphical-session.target,
      # restarted if it crashes; GDM auto-login (modules/gnome.nix) starts the session.
      programs.vextheater = {
        enable    = true;
        autostart = true;
        settings = {
          title      = "VexOS Theater";
          homeKey    = cfg.homeKey;
          background = "${wallpaper}";
          tiles      = map tileJson cfg.apps;
          submenus   = lib.mapAttrs (_: map tileJson) cfg.submenus;
        };
      };

      # A launcher that keeps crashing stops after five failures in a minute and
      # leaves the plain GNOME desktop, instead of flashing over it every two seconds.
      systemd.user.services.vextheater.unitConfig = {
        StartLimitIntervalSec = 60;
        StartLimitBurst       = 5;
      };

      # ── Home key ───────────────────────────────────────────────────────────
      # A GNOME custom shortcut, so it works over any app and from desktop mode, and
      # the ydotool key presses from CEC / the gamepad Guide button reach it like a
      # keyboard. gsd-media-keys keeps ONE custom-keybindings list per dconf database:
      # the desktop role lists its own in modules/gnome-desktop.nix, which the htpc
      # role does not import; a second list here would not merge with it.
      programs.dconf.profiles.user.databases = [
        {
          settings = {
            "org/gnome/settings-daemon/plugins/media-keys" = {
              custom-keybindings = [
                "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/vextheater-home/"
              ];
            };
            "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/vextheater-home" = {
              name    = "VexTheater home";
              command = "${lib.getExe vt.package} --home";
              binding = cfg.homeKey;
            };
          };
        }
      ];
    }

    (lib.mkIf (cfg.cec.enable || cfg.gamepad.homeButton) {
      programs.ydotool.enable = true;
    })

    (lib.mkIf cfg.cec.enable {
      systemd.services.vexos-htpc-cec = {
        description = "VexOS HTPC: HDMI-CEC remote to key presses";
        wantedBy    = [ "multi-user.target" ];
        after       = [ "ydotoold.service" ];
        requires    = [ "ydotoold.service" ];
        path        = [ pkgs.coreutils ];
        environment = ydotoolEnv;
        serviceConfig = {
          ExecStart           = cecBridge;
          DynamicUser         = true;
          SupplementaryGroups = [ "dialout" config.programs.ydotool.group ];
          Restart             = "always";
          RestartSec          = 5;
        };
      };
    })

    (lib.mkIf cfg.gamepad.homeButton {
      services.udev.extraRules = ''
        ACTION=="add", SUBSYSTEM=="input", KERNEL=="event*", ENV{ID_INPUT_JOYSTICK}=="1", TAG+="systemd", ENV{SYSTEMD_WANTS}+="vexos-htpc-guide@%k.service"
      '';

      systemd.services."vexos-htpc-guide@" = {
        description = "VexOS HTPC: gamepad Guide button to home key (%i)";
        bindsTo     = [ "dev-input-%i.device" ];
        after       = [ "dev-input-%i.device" "ydotoold.service" ];
        requires    = [ "ydotoold.service" ];
        environment = ydotoolEnv;
        serviceConfig = {
          ExecStart           = "${guideBridge} %i";
          DynamicUser         = true;
          SupplementaryGroups = [ "input" config.programs.ydotool.group ];
        };
      };
    })
  ]);
}
