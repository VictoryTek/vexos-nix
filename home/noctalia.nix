# home/noctalia.nix
# Noctalia v5 desktop shell (user layer), plus the two session daemons that
# must run inside the user session rather than system-wide.
# Active only when vexos.desktop.environment == "hyprland" — imported
# unconditionally by home-desktop.nix and gated internally, matching the shape
# of home/gnome-common.nix and the system-side DE modules.
#
# Why the Home Manager module and not the NixOS one: upstream ships both under
# the same option path (programs.noctalia), but only the home module carries
# `settings` (TOML) and `customPalettes` — the entire surface the later
# customisation phase needs — and only its service has restart-triggers on
# config change. The NixOS module's `recommendedServices` are all already
# enabled elsewhere in this repo (NetworkManager in modules/network.nix,
# Bluetooth in modules/desktop-common.nix, hardware.graphics in modules/gpu.nix,
# upower in modules/hyprland-desktop.nix), so importing it would only add a
# second definition of the same options.
{ pkgs, lib, inputs, osConfig, ... }:
{
  # Imports cannot be conditional — they are resolved before option values
  # exist — so this sits outside the mkIf below. The upstream module is inert
  # until programs.noctalia.enable is set, so non-Hyprland desktops are
  # unaffected by its presence.
  imports = [ inputs.noctalia.homeModules.default ];

  config = lib.mkIf (osConfig.vexos.desktop.environment == "hyprland") {
    # ── Noctalia shell ──────────────────────────────────────────────────────
    # systemd.enable binds the shell to config.wayland.systemd.target, which
    # resolves to graphical-session.target — activated by UWSM (see the
    # comment in modules/hyprland-desktop.nix; without UWSM this never starts).
    #
    # `settings` and `customPalettes` are deliberately left unset: this change
    # is the stock shell, to establish a booting baseline. Theming, bar layout,
    # widgets and keybinds are the follow-up customisation phase.
    programs.noctalia = {
      enable         = true;
      systemd.enable = true;
      package        = pkgs.noctalia;
    };

    # ── Polkit authentication agent ─────────────────────────────────────────
    # GNOME Shell provided this; Noctalia does not. Without it, any action
    # needing authentication (mounting a system disk, some Flatpak operations)
    # silently fails with no prompt.
    services.hyprpolkitagent.enable = true;

    # ── Removable-media automount ───────────────────────────────────────────
    # GNOME Shell auto-mounted USB drives; Noctalia does not. Requires
    # services.udisks2 system-side (set in modules/hyprland-desktop.nix).
    services.udiskie = {
      enable    = true;
      automount = true;
      tray      = "auto";
    };
  };
}
