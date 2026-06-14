# modules/razer.nix
# OpenRazer kernel driver + daemon support for Razer peripherals (keyboards, mice, headsets).
# Loads out-of-tree kernel modules automatically, registers udev rules, and starts
# the per-user openrazer-daemon systemd service with the graphical session.
# polychromatic provides the GTK GUI for lighting / device configuration.
#
# Desktop-only: import only from configuration-desktop.nix.
{ config, pkgs, lib, ... }:
{
  hardware.openrazer = {
    enable = true;
    users                   = [ config.vexos.user.name ];
    syncEffectsEnabled      = true;
    devicesOffOnScreensaver = true;
  };

  environment.systemPackages = with pkgs; [
    polychromatic  # GTK GUI frontend for OpenRazer (lighting, DPI, macros)
  ];
}
