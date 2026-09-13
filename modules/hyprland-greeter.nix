# modules/hyprland-greeter.nix
# GDM login greeter for the Hyprland desktop role. Active only when
# vexos.desktop.environment == "hyprland" (see modules/desktop-environment.nix)
# — same gate modules/hyprland-desktop.nix uses, split into its own file
# because the greeter is a separate subsystem from the compositor/shell.
#
# Reuses GDM (modules/gnome.nix's display manager) instead of a greetd-backed
# greeter (DMS greeter, then ReGreet — see
# .github/docs/subagent_docs/regreet_greeter_migration_spec.md and
# .github/docs/subagent_docs/hyprland_gdm_greeter_migration_spec.md for that
# history) so the Hyprland role gets the exact same login screen GNOME already
# has, logo/branding included (modules/branding-display.nix gates its GDM
# dconf profile to both "gnome" and "hyprland"). GDM does not require
# services.xserver.enable to run a pure-Wayland session — it runs its own
# Wayland compositor for the login screen and only needs Xwayland (already
# enabled via programs.hyprland.xwayland.enable) for X11 apps inside the
# session proper.
#
# NOTE: the session picker still lists TWO Hyprland entries — "Hyprland" and
# "Hyprland (UWSM)" (see modules/hyprland-desktop.nix, which registers both).
# SELECT THE UWSM ONE, same gotcha as before; this module doesn't change that.
{ config, lib, ... }:
let
  isHyprland = config.vexos.desktop.environment == "hyprland";
in
{
  config = lib.mkIf isHyprland {
    services.displayManager.gdm.enable = true;

    # Do not restart GDM during `nixos-rebuild switch`. Otherwise, whenever the
    # display-manager unit or one of its dependencies changes in the new
    # closure, switch-to-configuration tears down the running graphical
    # session mid-rebuild and drops the user to a black VT with a blinking
    # cursor until GDM comes back. The new GDM configuration takes effect on
    # the next reboot instead — which the `just switch` flow already prompts
    # for on completion. Mirrors modules/gnome.nix's identical setting.
    systemd.services.display-manager.restartIfChanged = false;
  };
}
