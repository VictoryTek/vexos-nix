# modules/cosmic-desktop.nix
# COSMIC desktop environment (System76) for the desktop role. Active only
# when vexos.desktop.environment == "cosmic" (see
# modules/desktop-environment.nix). DE-agnostic content (fonts, printing,
# Bluetooth, auto-login, Moonlight, base XDG portal enable) comes from
# modules/desktop-common.nix, imported transitively via modules/gnome.nix's
# import list (present regardless of DE, only its `config` is gated).
#
# No remote-desktop setup here — Sunshine/Moonlight (modules/sunshine.nix)
# is the project's remote-access solution across all desktop environments.
{ config, pkgs, lib, ... }:
let
  isCosmic = config.vexos.desktop.environment == "cosmic";
in
{
  config = lib.mkIf isCosmic {
    services.desktopManager.cosmic.enable          = true;
    services.desktopManager.cosmic.xwayland.enable = true;
    services.displayManager.cosmic-greeter.enable  = true;

    xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-cosmic ];

    # ── Wallpaper/branding ──────────────────────────────────────────────────
    # COSMIC has no dconf-equivalent system profile — cosmic-bg reads its
    # wallpaper config from the user's own ~/.config/cosmic/... RON files.
    # Deploy the same vexos-wallpapers store path branding-display.nix builds
    # as the default background the first time the user's graphical session
    # starts, seeded once rather than overwriting the file on every login
    # (which would clobber any user customisation).
    systemd.user.services.vexos-cosmic-wallpaper = {
      description = "Seed default COSMIC wallpaper (once)";
      wantedBy    = [ "graphical-session.target" ];
      after       = [ "graphical-session.target" ];
      serviceConfig = {
        Type      = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        CFG_DIR="$HOME/.config/cosmic/com.system76.CosmicBackground/v1"
        STAMP="$HOME/.config/cosmic/.vexos-wallpaper-seeded"
        [ -f "$STAMP" ] && exit 0
        mkdir -p "$CFG_DIR"
        # RON format per cosmic-bg's WallpaperState — verify against the
        # installed cosmic-bg version on first boot and adjust if the schema
        # has changed; this is a best-effort default, not a guaranteed match.
        cat > "$CFG_DIR/wallpapers" <<EOF
        [("all", Path("/run/current-system/sw/share/backgrounds/vexos/vex-bb-dark.jxl"))]
        EOF
        touch "$STAMP"
      '';
    };
  };
}
