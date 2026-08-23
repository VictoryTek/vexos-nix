# modules/hyprland-desktop.nix
# Hyprland compositor + DankMaterialShell (Quickshell-based desktop shell) +
# dms-greeter (matching Quickshell-based greetd greeter) for the desktop
# role — the same stack combination used by Omarchy. Active only when
# vexos.desktop.environment == "hyprland" (see modules/desktop-environment.nix).
# DE-agnostic content (fonts, printing, Bluetooth, auto-login, Moonlight,
# base XDG portal enable) comes from modules/desktop-common.nix, imported
# transitively via modules/gnome.nix's import list (present regardless of
# DE, only its `config` is gated).
#
# No remote-desktop setup here — Sunshine/Moonlight (modules/sunshine.nix)
# is the project's remote-access solution across all desktop environments.
{ config, pkgs, lib, ... }:
let
  isHyprland = config.vexos.desktop.environment == "hyprland";
in
{
  config = lib.mkIf isHyprland {
    programs.hyprland = {
      enable         = true;
      xwayland.enable = true;
      withUWSM       = true;
    };

    programs.dms-shell.enable = true;

    services.displayManager.dms-greeter = {
      enable                  = true;
      compositor.name          = "hyprland";
    };

    xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-hyprland ];

    # ── Wallpaper/branding ──────────────────────────────────────────────────
    # Hyprland has no dconf-equivalent system profile, and NixOS's
    # programs.hyprland does not manage ~/.config/hypr/hyprland.conf (Hyprland
    # generates its own default there on first run). Deploy a default
    # hyprpaper config pointing at the same vexos-wallpapers store path
    # branding-display.nix builds, seeded once on first login so it never
    # clobbers user customisation afterward.
    # NOTE: `exec-once = hyprpaper` must still be added to hyprland.conf by
    # hand (or via a future home-manager-managed hyprland.conf) — this
    # service only seeds hyprpaper's own config file, it does not launch it.
    environment.systemPackages = [ pkgs.hyprpaper ];
    systemd.user.services.vexos-hyprland-wallpaper = {
      description = "Seed default Hyprland wallpaper (once)";
      wantedBy    = [ "graphical-session.target" ];
      after       = [ "graphical-session.target" ];
      serviceConfig = {
        Type            = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        CFG_DIR="$HOME/.config/hypr"
        STAMP="$CFG_DIR/.vexos-wallpaper-seeded"
        [ -f "$STAMP" ] && exit 0
        mkdir -p "$CFG_DIR"
        cat > "$CFG_DIR/hyprpaper.conf" <<EOF
        preload = /run/current-system/sw/share/backgrounds/vexos/vex-bb-dark.jxl
        wallpaper = ,/run/current-system/sw/share/backgrounds/vexos/vex-bb-dark.jxl
        EOF
        touch "$STAMP"
      '';
    };
  };
}
