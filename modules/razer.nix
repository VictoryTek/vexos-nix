# modules/razer.nix
# OpenRazer kernel driver + daemon support for Razer peripherals (keyboards, mice, headsets).
# Loads out-of-tree kernel modules automatically, registers udev rules, and starts
# the per-user openrazer-daemon systemd service with the graphical session.
# polychromatic provides the GTK GUI for lighting / device configuration.
#
# Desktop-only: import only from configuration-desktop.nix.
#
# Patch note: openrazer 3.10.3 (nixpkgs 25.11) doesn't compile against Linux 6.18.32+
# because hid_report_raw_event() gained a bufsize parameter (upstream commit 2c85c61,
# backported into 6.18.32 and 7.0.9). The fix (openrazer commit ff30624, released in
# 3.12.3) is in nixpkgs master/26.05 but not 25.11. Apply it here via overlay until
# nixpkgs 25.11 is bumped or the backport lands. Remove this overlay once the nixpkgs
# input is upgraded to a version that includes the fix.
# Tracking: https://github.com/NixOS/nixpkgs/issues/523973
{ config, pkgs, lib, ... }:
{
  nixpkgs.overlays = [
    (final: prev: {
      linuxKernel = prev.linuxKernel // {
        packages = builtins.mapAttrs (_name: kpkgs:
          if kpkgs ? openrazer then
            kpkgs // {
              openrazer = kpkgs.openrazer.overrideAttrs (old: {
                patches = (old.patches or []) ++ [
                  ../patches/openrazer-hid-report-raw-event-6_18.patch
                ];
              });
            }
          else kpkgs
        ) prev.linuxKernel.packages;
      };
    })
  ];

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
