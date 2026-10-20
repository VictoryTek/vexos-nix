# modules/htpc-theater.nix
# HTPC "theater mode": a Roku-style full-screen Flex Launcher running in a
# minimal labwc session, alongside GNOME as "desktop mode" — the Steam Deck
# Gaming Mode / Desktop Mode model.
#
# How mode switching works:
#   - greetd replaces GDM. Its initial_session (autologin) runs
#     vexos-htpc-session, which reads /run/vexos-htpc/session and starts
#     either the theater session or GNOME.
#   - vexos-session-select <theater|desktop> writes that file and terminates
#     the current session (cf. steamos-session-select).
#   - greetd runs initial_session only once per start, so the "greeter" is
#     `true`: it exits at once, greetd exits, systemd restarts it, and
#     ExecStartPre clears greetd's runfile so autologin runs again.
#   - The state file lives on /run, so every boot starts in defaultMode.
#
# Imported only by configuration-htpc.nix.
{ config, pkgs, lib, ... }:
let
  cfg   = config.vexos.htpc.theater;
  theme = cfg.theme;

  flexAssets = "${pkgs.flex-launcher}/share/flex-launcher/assets";
  kora       = "${pkgs.kora-icon-theme}/share/icons/kora";

  # Default tile icons gathered under one short store path, keeping config
  # lines under inih's length limit.
  icons = pkgs.linkFarm "vexos-htpc-icons" {
    "youtube.svg" = "${kora}/apps/scalable/youtube.svg";
    "browser.png" = "${pkgs.vexos.brave-origin}/share/icons/hicolor/256x256/apps/brave-origin.png";
    "twitch.svg"  = "${kora}/apps/scalable/gnome-twitch.svg";
    "desktop.svg" = "${kora}/apps/scalable/preferences-desktop-display.svg";
    "plex.png"    = "${flexAssets}/icons/plex.png";
    "power.png"   = "${flexAssets}/icons/system.png";
    "restart.png" = "${flexAssets}/icons/restart.png";
  };
  brave      = lib.getExe pkgs.vexos.brave-origin;

  # Same artwork as the HTPC desktop wallpaper. Flex Launcher loads images via
  # SDL_image, which may lack JPEG XL, so convert to JPEG at build time.
  wallpaper = pkgs.runCommand "vexos-htpc-theater-wallpaper.jpg" { nativeBuildInputs = [ pkgs.libjxl ]; } ''
    djxl ${../wallpapers/htpc/vex-bb-dark.jxl} $out --jpeg_quality=92
  '';

  stateFile = "/run/vexos-htpc/session";

  # Linux evdev key codes for ydotool (CEC and gamepad Guide mapping).
  # Its attribute names are also the allowed homeKey values (XKB key names,
  # which is what labwc keybinds use).
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
  mkWebApp = { name, icon, url, tvUserAgent ? false }: {
    inherit name icon;
    command = toString (pkgs.writeShellScript "vexos-htpc-webapp-${slug name}" ''
      dir="$HOME/.local/share/vexos-htpc/webapps/${slug name}"
      mkdir -p "$dir"
      [ -e "$dir/Local State" ] || printf '%s\n' '{"brave":{"widevine_opted_in":true}}' > "$dir/Local State"
      exec ${brave} --kiosk --app=${lib.escapeShellArg url} --user-data-dir="$dir" ${
        lib.optionalString tvUserAgent "--user-agent=${lib.escapeShellArg smartTvUserAgent}"}
    '');
  };

  appType = lib.types.submodule {
    options = {
      name = lib.mkOption {
        type        = lib.types.str;
        description = "Tile title.";
      };
      icon = lib.mkOption {
        type        = lib.types.path;
        description = "Tile icon (PNG/WebP with transparency, or SVG). A sibling <icon>_selected.<ext> is shown while the tile is highlighted.";
      };
      command = lib.mkOption {
        type        = lib.types.str;
        description = "Shell command, a .desktop file path (optionally followed by ;Action), or a Flex Launcher special command (:submenu <Name>, :back, :home, :fork <cmd>, :shutdown, :restart).";
      };
    };
  };

  colorType = lib.types.strMatching "#[0-9A-Fa-f]{6}";

  # ── Flex Launcher config.ini ─────────────────────────────────────────────
  # Flex Launcher parses with nixpkgs' inih: lines are limited to 198
  # characters and " ;" starts an inline comment. Commands therefore go into
  # store-path wrapper scripts (other special commands and .desktop paths
  # stay as-is), and titles/icons/menu names may not contain ';' (assertions).
  wrapCommand = name: cmd:
    toString (pkgs.writeShellScript "vexos-htpc-app-${slug name}" "exec ${cmd}");

  entryCommand = app:
    if lib.hasPrefix ":fork " app.command
    then ":fork ${wrapCommand app.name (lib.removePrefix ":fork " app.command)}"
    else if lib.hasPrefix ":" app.command || builtins.match "[^ ]*\\.desktop(;.*)?" app.command != null
    then app.command
    else wrapCommand app.name app.command;

  menu = name: apps:
    [ "" "[${name}]" ]
    ++ lib.imap1 (i: app: "Entry${toString i}=${app.name};${app.icon};${entryCommand app}") apps;

  pct = n: "${toString n}%";

  iniLines = [
    "[General]"
    "DefaultMenu=Main"
    "VSync=true"
    "OnLaunch=Blank"
    "InhibitOSScreensaver=true"
    ""
    "[Background]"
    "Mode=${theme.background.mode}"
    "Color=${theme.background.color}"
  ]
  ++ lib.optional (theme.background.image != null) "Image=${theme.background.image}"
  ++ lib.optional (theme.background.slideshowDirectory != null)
       "SlideshowDirectory=${theme.background.slideshowDirectory}"
  ++ [
    ""
    "[Layout]"
    "MaxButtons=${toString theme.maxButtons}"
    "IconSize=${toString theme.iconSize}"
    ""
    "[Titles]"
    "Enabled=true"
    "Font=${theme.titles.font}"
    "FontSize=${toString theme.titles.fontSize}"
    "Color=${theme.titles.color}"
    ""
    "[Highlight]"
    "Enabled=true"
    "FillColor=${theme.highlight.fillColor}"
    "FillOpacity=${pct theme.highlight.fillOpacity}"
    "OutlineSize=${toString theme.highlight.outlineSize}"
    "OutlineColor=${theme.highlight.outlineColor}"
    "CornerRadius=${toString theme.highlight.cornerRadius}"
    # Unset paddings stay -1, which Flex Launcher's geometry check turns into
    # a -1 outline that disables CornerRadius; set upstream's sample values.
    "VPadding=30"
    "HPadding=30"
    ""
    "[Clock]"
    "Enabled=${lib.boolToString theme.clock.enable}"
    "Font=${theme.titles.font}"
    "FontColor=${theme.titles.color}"
    ""
    "[Gamepad]"
    "Enabled=${lib.boolToString cfg.gamepad.enable}"
    "DeviceIndex=-1"
    "LStickX-=:left"
    "LStickX+=:right"
    "ButtonDPadLeft=:left"
    "ButtonDPadRight=:right"
    "ButtonA=:select"
    "ButtonB=:back"
  ]
  ++ menu "Main" cfg.apps
  ++ lib.concatLists (lib.mapAttrsToList menu cfg.submenus);

  flexConfig = pkgs.writeText "flex-launcher.ini" (lib.concatStringsSep "\n" iniLines + "\n");

  reservedSections = [
    "General" "Background" "Layout" "Titles" "Highlight" "Scroll Indicators"
    "Clock" "Screensaver" "Hotkeys" "Gamepad" "Main"
  ];
  allApps = cfg.apps ++ lib.concatLists (lib.attrValues cfg.submenus);
  hasBadChars = s: lib.hasInfix ";" s || lib.hasInfix "\n" s;

  # ── labwc: home key closes the focused app (never the launcher) ──────────
  labwcConfig = pkgs.writeTextDir "rc.xml" ''
    <?xml version="1.0"?>
    <labwc_config>
      <keyboard>
        <keybind key="${cfg.homeKey}">
          <action name="If">
            <query title="Flex Launcher"/>
            <else>
              <action name="Close"/>
            </else>
          </action>
        </keybind>
      </keyboard>
      <windowRules>
        <windowRule identifier="*" serverDecoration="no"/>
        <windowRule identifier="*">
          <action name="Maximize"/>
          <action name="HideCursor"/>
        </windowRule>
      </windowRules>
    </labwc_config>
  '';

  # Keeps Flex Launcher running for as long as labwc does. Its sizes are fixed
  # pixels, so each start rescales icon, font and highlight padding from the
  # 1920x1080 reference to the current output (the smaller axis ratio wins).
  launcherLoop = pkgs.writeShellScript "vexos-htpc-launcher-loop" ''
    conf="$XDG_RUNTIME_DIR/vexos-flex-launcher.ini"
    while kill -0 "$LABWC_PID" 2>/dev/null; do
      read -r w h < <(${lib.getExe pkgs.wlr-randr} 2>/dev/null |
        ${pkgs.gawk}/bin/awk '/current/ { split($1, a, "x"); print a[1], a[2]; exit }')
      w=''${w:-1920}; h=''${h:-1080}
      pct=$(( w * 100 / 1920 < h * 100 / 1080 ? w * 100 / 1920 : h * 100 / 1080 ))
      ${pkgs.gawk}/bin/awk -F= -v pct="$pct" '
        $1 ~ /^(IconSize|FontSize|VPadding|HPadding)$/ { $2 = int($2 * pct / 100) }
        { print }' OFS== ${flexConfig} > "$conf"
      ${lib.getExe pkgs.flex-launcher} -c "$conf"
      sleep 1
    done
  '';

  theaterSession = pkgs.writeShellScriptBin "vexos-theater-session" ''
    exec ${lib.getExe pkgs.labwc} -C ${labwcConfig} -s ${launcherLoop}
  '';

  theaterSessionPackage = pkgs.writeTextFile {
    name        = "vexos-theater-session-desktop";
    destination = "/share/wayland-sessions/vexos-theater.desktop";
    text = ''
      [Desktop Entry]
      Name=VexOS Theater
      Comment=Full-screen TV launcher (Flex Launcher on labwc)
      Exec=${lib.getExe theaterSession}
      Type=Application
      DesktopNames=labwc;wlroots
    '';
    passthru.providedSessions = [ "vexos-theater" ];
  };

  # Started by greetd's initial_session; picks the mode from the state file.
  sessionLauncher = pkgs.writeShellApplication {
    name          = "vexos-htpc-session";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      mode=$(cat ${stateFile} 2>/dev/null || true)
      case "$mode" in
        theater|desktop) ;;
        *) mode=${cfg.defaultMode} ;;
      esac

      if [ "$mode" = desktop ]; then
        export XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=GNOME XDG_SESSION_DESKTOP=gnome DESKTOP_SESSION=gnome
        ${pkgs.gnome-session}/bin/gnome-session || true
        # A plain GNOME "Log Out" returns to theater mode, like leaving
        # Desktop Mode on a Steam Deck.
        printf 'theater\n' > ${stateFile}
      else
        exec ${lib.getExe theaterSession}
      fi
    '';
  };

  sessionSelect = pkgs.writeShellApplication {
    name          = "vexos-session-select";
    runtimeInputs = [ pkgs.coreutils pkgs.systemd ];
    text = ''
      case "''${1:-}" in
        theater|desktop) ;;
        *) echo "usage: vexos-session-select <theater|desktop>" >&2; exit 2 ;;
      esac

      printf '%s\n' "$1" > ${stateFile}

      # End the graphical session; greetd restarts and autologs into the
      # selected mode.
      session=$(loginctl show-user "$(id -u)" -p Display --value 2>/dev/null || true)
      session=''${session:-''${XDG_SESSION_ID:-}}
      if [ -z "$session" ]; then
        echo "vexos-session-select: no graphical session found to end" >&2
        exit 1
      fi
      exec loginctl terminate-session "$session"
    '';
  };

  theaterDesktopItem = pkgs.makeDesktopItem {
    name        = "vexos-theater-mode";
    desktopName = "Theater Mode";
    comment     = "Switch to the full-screen TV launcher";
    exec        = "${lib.getExe sessionSelect} theater";
    icon        = "video-display";
    categories  = [ "System" ];
  };

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
  options.vexos.htpc.theater = {
    enable = lib.mkEnableOption "HTPC theater mode (Flex Launcher on labwc) with GNOME as desktop mode, switched via greetd autologin" // { default = true; };

    user = lib.mkOption {
      type        = lib.types.str;
      default     = config.vexos.user.name;
      defaultText = lib.literalExpression "config.vexos.user.name";
      description = "User that greetd logs in automatically.";
    };

    defaultMode = lib.mkOption {
      type        = lib.types.enum [ "theater" "desktop" ];
      default     = "theater";
      description = "Mode every boot starts in.";
    };

    apps = lib.mkOption {
      type        = lib.types.listOf appType;
      description = ''
        Main menu tiles. The defaults are module definitions, so tiles you
        define are added (before Desktop Mode and Power); use lib.mkForce to
        replace the whole list.
      '';
    };

    submenus = lib.mkOption {
      type        = lib.types.attrsOf (lib.types.listOf appType);
      description = "Flex Launcher submenus (name → tiles), opened by a tile with command \":submenu <name>\".";
    };

    homeKey = lib.mkOption {
      type        = lib.types.enum (lib.attrNames keyCodes);
      default     = "F10";
      description = "Key that closes the focused app and returns to the launcher.";
    };

    gamepad = {
      enable = lib.mkEnableOption "gamepad control of the launcher" // { default = true; };
      homeButton = lib.mkEnableOption "mapping the gamepad Guide button to the home key (via ydotool)";
    };

    cec.enable = lib.mkEnableOption "HDMI-CEC TV remote input via libcec (needs a CEC adapter such as a Pulse-Eight USB-CEC)";

    mkWebApp = lib.mkOption {
      type        = lib.types.raw;
      readOnly    = true;
      default     = mkWebApp;
      description = "Helper: mkWebApp { name; icon; url; tvUserAgent ? false; } → an app tile that opens url in a Brave kiosk window.";
    };

    theme = {
      background = {
        mode = lib.mkOption {
          type    = lib.types.enum [ "Color" "Image" "Slideshow" "Transparent" ];
          default = "Image";
          description = "Background mode.";
        };
        color = lib.mkOption {
          type    = colorType;
          default = "#000000";
          description = "Background color (Color mode).";
        };
        image = lib.mkOption {
          type    = lib.types.nullOr lib.types.path;
          default = wallpaper;
          defaultText = lib.literalExpression "the HTPC dark wallpaper, converted to JPEG";
          description = "Background image (Image mode).";
        };
        slideshowDirectory = lib.mkOption {
          type    = lib.types.nullOr lib.types.path;
          default = null;
          description = "Directory of background images (Slideshow mode).";
        };
      };
      iconSize = lib.mkOption {
        type    = lib.types.ints.between 16 1024;
        default = 256;
        description = "Tile icon size in pixels at 1920x1080; scaled down on smaller displays (likewise the title font size and highlight padding).";
      };
      maxButtons = lib.mkOption {
        type    = lib.types.ints.positive;
        default = 5;
        description = "Tiles visible at once; more scroll.";
      };
      titles = {
        font = lib.mkOption {
          type    = lib.types.path;
          default = "${flexAssets}/fonts/OpenSans-Regular.ttf";
          defaultText = lib.literalExpression ''"''${pkgs.flex-launcher}/share/flex-launcher/assets/fonts/OpenSans-Regular.ttf"'';
          description = "TTF font for tile titles and the clock.";
        };
        fontSize = lib.mkOption {
          type    = lib.types.ints.positive;
          default = 36;
          description = "Title font size.";
        };
        color = lib.mkOption {
          type    = colorType;
          default = "#FFFFFF";
          description = "Title and clock color.";
        };
      };
      highlight = {
        fillColor = lib.mkOption {
          type    = colorType;
          default = "#FFFFFF";
          description = "Highlight fill color.";
        };
        fillOpacity = lib.mkOption {
          type    = lib.types.ints.between 0 100;
          default = 25;
          description = "Highlight fill opacity, in percent.";
        };
        outlineSize = lib.mkOption {
          type    = lib.types.ints.unsigned;
          default = 0;
          description = "Highlight outline width in pixels (must be 0 when cornerRadius is set).";
        };
        outlineColor = lib.mkOption {
          type    = colorType;
          default = "#0000FF";
          description = "Highlight outline color.";
        };
        cornerRadius = lib.mkOption {
          type    = lib.types.ints.unsigned;
          default = 20;
          description = "Highlight corner radius in pixels.";
        };
      };
      clock.enable = lib.mkEnableOption "the on-screen clock" // { default = true; };
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      assertions = [
        {
          assertion = theme.highlight.cornerRadius == 0 || theme.highlight.outlineSize == 0;
          message   = "vexos.htpc.theater.theme.highlight: cornerRadius requires outlineSize = 0.";
        }
        {
          assertion = theme.background.mode != "Image" || theme.background.image != null;
          message   = "vexos.htpc.theater.theme.background.image must be set when mode = \"Image\".";
        }
        {
          assertion = theme.background.mode != "Slideshow" || theme.background.slideshowDirectory != null;
          message   = "vexos.htpc.theater.theme.background.slideshowDirectory must be set when mode = \"Slideshow\".";
        }
        {
          assertion = !(lib.any (n: lib.elem n reservedSections || hasBadChars n || lib.hasInfix "]" n) (lib.attrNames cfg.submenus));
          message   = "vexos.htpc.theater.submenus: names must not contain ';', ']' or newlines, nor be one of: ${lib.concatStringsSep ", " reservedSections}.";
        }
        {
          assertion = !(lib.any (a: hasBadChars a.name || hasBadChars "${a.icon}") allApps);
          message   = "vexos.htpc.theater: app names and icon paths must not contain ';' or newlines.";
        }
        {
          assertion = lib.all (l: lib.stringLength l <= 198) iniLines;
          message   = "vexos.htpc.theater: a generated Flex Launcher config line exceeds 198 characters (inih limit): ${
            lib.concatStringsSep ", " (lib.filter (l: lib.stringLength l > 198) iniLines)}";
        }
      ];

      vexos.htpc.theater.apps = lib.mkMerge [ [
        (mkWebApp {
          name        = "YouTube";
          icon        = "${icons}/youtube.svg";
          url         = "https://www.youtube.com/tv";
          tvUserAgent = true;
        })
        {
          name    = "Plex";
          icon    = "${icons}/plex.png";
          command = lib.getExe pkgs.plex-htpc;
        }
        (mkWebApp {
          name = "Twitch";
          icon = "${icons}/twitch.svg";
          url  = "https://www.twitch.tv";
        })
        {
          name    = "Browser";
          icon    = "${icons}/browser.png";
          command = "${brave} --start-fullscreen";
        }
      ] (lib.mkAfter [
        {
          name    = "Desktop Mode";
          icon    = "${icons}/desktop.svg";
          command = ":fork ${lib.getExe sessionSelect} desktop";
        }
        {
          name    = "Power";
          icon    = "${icons}/power.png";
          command = ":submenu Power";
        }
      ]) ];

      # No Sleep tile: modules/system-nosleep.nix masks every sleep target.
      vexos.htpc.theater.submenus.Power = [
        { name = "Shutdown"; icon = "${icons}/power.png";   command = ":shutdown"; }
        { name = "Restart";  icon = "${icons}/restart.png"; command = ":restart"; }
      ];

      environment.systemPackages = [
        pkgs.labwc
        pkgs.flex-launcher
        pkgs.plex-htpc
        theaterSession
        sessionSelect
        theaterDesktopItem
      ];

      services.displayManager.sessionPackages = [ theaterSessionPackage ];
      xdg.portal.config.labwc.default = [ "gtk" ];

      # ── greetd replaces GDM (modules/gnome.nix) ────────────────────────────
      services.displayManager.gdm.enable       = lib.mkForce false;
      services.displayManager.autoLogin.enable = lib.mkForce false;

      services.greetd = {
        enable = true;
        settings = {
          initial_session = {
            user    = cfg.user;
            command = lib.getExe sessionLauncher;
          };
          # No greeter: it exits at once, greetd exits, and systemd restarts
          # greetd straight back into initial_session.
          default_session.command = "${pkgs.coreutils}/bin/true";
        };
      };

      systemd.services.greetd = {
        # pam_systemd falls back to the process environment, so logind
        # registers the session as Wayland (GNOME Shell needs this).
        environment.XDG_SESSION_TYPE = "wayland";
        serviceConfig = {
          ExecStartPre = "${pkgs.coreutils}/bin/rm -f /run/greetd.run";
          Restart      = "always";
          RestartSec   = 1;
        };
        # Room for normal back-and-forth switching; a real crash loop stops.
        startLimitBurst       = 10;
        startLimitIntervalSec = 60;
        # Never start on top of a running GDM: a live switch from the old
        # GDM generation (from any update path) skips greetd, and GDM keeps
        # the session until the next boot, when /run is empty again.
        unitConfig.ConditionPathExists = "!/run/gdm/gdm.pid";
      };

      # User-writable mode file, recreated with defaultMode on every boot.
      systemd.tmpfiles.rules = [
        "d /run/vexos-htpc 0755 ${cfg.user} users -"
        "f ${stateFile} 0644 ${cfg.user} users - ${cfg.defaultMode}"
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
