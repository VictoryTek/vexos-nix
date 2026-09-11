# modules/hyprland-greeter.nix
# ReGreet login greeter for the Hyprland desktop role. Active only when
# vexos.desktop.environment == "hyprland" (see modules/desktop-environment.nix)
# — same gate modules/hyprland-desktop.nix uses, split into its own file
# because it grew past a couple of lines living inline there.
#
# Replaces the DankMaterialShell (DMS) greeter, which kept running after the
# shell itself moved to Noctalia (home/noctalia.nix) — the greeter is a
# separate subsystem from the shell and was never migrated. See
# .github/docs/subagent_docs/regreet_greeter_migration_spec.md for the
# evaluation of alternatives (dank-greeter, noctalia-greeter) and why ReGreet
# was chosen.
#
# ReGreet is packaged in nixpkgs directly (programs.regreet) — no flake input
# needed. It runs under `cage` (a minimal kiosk Wayland compositor) as the
# greeter's OWN compositor; this is unrelated to which session the user picks
# afterward. The upstream module sets services.greetd itself via mkDefault,
# so — same rule the DMS greeter followed — we must NOT declare
# services.greetd here ourselves.
#
# NOTE: the session picker still lists TWO Hyprland entries — "Hyprland" and
# "Hyprland (UWSM)" (see modules/hyprland-desktop.nix, which registers both).
# SELECT THE UWSM ONE, same gotcha as before; this module doesn't change that.
{ config, pkgs, lib, ... }:
let
  isHyprland = config.vexos.desktop.environment == "hyprland";

  role       = config.vexos.branding.role;
  pixmapsDir = ../files/pixmaps + "/${role}";
  logoPng    = pixmapsDir + "/vex.png";

  # Purpose-built cyberpunk background for the greeter (not one of the
  # desktop wallpapers) — see files/regreet/background.svg. Rasterized at
  # build time so ReGreet's GStreamer/gdk-pixbuf loader always gets a plain
  # PNG regardless of which image plugins happen to be installed.
  backgroundPng = pkgs.runCommand "vexos-regreet-background" {
    nativeBuildInputs = [ pkgs.resvg ];
  } ''
    mkdir -p $out
    resvg --width 1920 --height 1080 ${../files/regreet/background.svg} $out/background.png
  '';

  # VexOS Neo-Cyberpunk Dark palette (files/dms/vexos-neo-cyberpunk.json) —
  # kept as named values so every CSS rule below traces back to the same
  # source of truth instead of scattered hex literals.
  palette = {
    primary          = "#05F4FA";
    onPrimary        = "#00141A";
    secondary        = "#DD4014";
    surface          = "#0B1526";
    surfaceText      = "#E7EEF5";
    surfaceVariant   = "#16233A";
    outline          = "#5D7190";
    error            = "#FF4D6D";
  };

  regreetCss = ''
    window, #background {
      background-color: ${palette.surface};
    }

    /* Login card + clock panel share the .background class upstream. */
    .background {
      background-color: alpha(${palette.surface}, 0.82);
      border: 1px solid alpha(${palette.primary}, 0.35);
      border-radius: 14px;
      box-shadow: 0 0 32px alpha(${palette.primary}, 0.15);
      color: ${palette.surfaceText};
    }

    #message_label, #session_label, #input_label {
      color: ${palette.surfaceText};
    }

    #username_entry, #session_entry, #secret_entry, #visible_entry,
    #usernames_box, #sessions_box {
      background-color: alpha(${palette.surfaceVariant}, 0.9);
      color: ${palette.surfaceText};
      border: 1px solid alpha(${palette.outline}, 0.4);
      border-radius: 8px;
    }
    #username_entry:focus, #session_entry:focus, #secret_entry:focus,
    #visible_entry:focus {
      border-color: ${palette.primary};
      box-shadow: 0 0 0 2px alpha(${palette.primary}, 0.25);
    }

    #cancel_button {
      background-color: alpha(${palette.surfaceVariant}, 0.9);
      color: ${palette.surfaceText};
      border: 1px solid alpha(${palette.outline}, 0.4);
      border-radius: 8px;
    }

    #login_button.suggested-action {
      background-image: none;
      background-color: ${palette.primary};
      color: ${palette.onPrimary};
      border: none;
      border-radius: 8px;
      font-weight: 600;
    }
    #login_button.suggested-action:hover {
      background-color: alpha(${palette.primary}, 0.85);
    }

    .destructive-action {
      background-image: none;
      background-color: alpha(${palette.error}, 0.15);
      color: ${palette.error};
      border: 1px solid alpha(${palette.error}, 0.4);
      border-radius: 8px;
    }
    .destructive-action:hover {
      background-color: alpha(${palette.error}, 0.3);
    }

    #notif_info {
      background-color: alpha(${palette.error}, 0.12);
      border: 1px solid alpha(${palette.error}, 0.4);
      border-radius: 8px;
    }
    #notif_label {
      color: ${palette.error};
    }

    /* Clock panel doubles as the login-screen logo badge — ReGreet has no
       dedicated logo widget (verified against upstream source), so the
       project mark is painted into this panel's top padding via CSS. */
    #clock_frame {
      background-color: alpha(${palette.surface}, 0.85);
      border: 1px solid alpha(${palette.primary}, 0.3);
      border-radius: 0 0 14px 14px;
      padding: 44px 24px 10px 24px;
      background-image: url("${logoPng}");
      background-repeat: no-repeat;
      background-position: top center;
      background-size: 150px 50px;
    }
    #clock_frame label {
      color: ${palette.primary};
      font-weight: 600;
      text-shadow: 0 0 12px alpha(${palette.primary}, 0.6);
    }
  '';
in
{
  config = lib.mkIf isHyprland {
    programs.regreet = {
      enable = true;

      settings = {
        background = {
          path = "${backgroundPng}/background.png";
          fit  = "Cover";
        };
        appearance.greeting_msg = "Welcome to VexOS";
        # Not set via settings.GTK (the module builds that key itself from
        # font/theme/iconTheme/cursorTheme below) — a hand-written
        # settings.GTK.* here would collide with it.
        GTK.application_prefer_dark_theme = true;
      };

      font = {
        package = pkgs.inter;
        name    = "Inter";
        size    = 13;
      };

      extraCss = regreetCss;
    };

    # Same rationale as the DMS greeter had: a switch that restarts greetd
    # mid-session blackscreens the running compositor. New greeter config
    # applies on the next reboot instead.
    systemd.services.greetd.restartIfChanged = false;
  };
}
