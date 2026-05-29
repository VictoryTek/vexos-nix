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
      # linuxPackages_6_18 is the top-level alias used by boot.kernelPackages.
      # Use .extend (the standard API for kernel package sets) so that
      # config.boot.kernelPackages.openrazer resolves to the patched derivation,
      # which is what hardware.openrazer picks up via boot.extraModulePackages.
      linuxPackages_6_18 = prev.linuxPackages_6_18.extend (lpFinal: lpPrev: {
        openrazer = lpPrev.openrazer.overrideAttrs (old: {
          # Fix: hid_report_raw_event() gained a bufsize parameter in Linux 6.18.32+
          # (kernel commit 2c85c61, backported into 6.18.32). openrazer 3.10.3 calls
          # the old 5-arg form; add the include and pass sizeof(xdata) as bufsize.
          # Fixed upstream in openrazer 3.12.3 / nixpkgs 26.05 (PR #523308 / #524105).
          # Remove this override once the nixpkgs input is bumped to 26.05+.
          postPatch = (old.postPatch or "") + ''
            sed -i 's|#include <linux/input-event-codes.h>|#include <linux/input-event-codes.h>\n#include <linux/version.h>|' driver/razerkbd_driver.c
            sed -i 's|hid_report_raw_event(hdev, HID_INPUT_REPORT, xdata, sizeof(xdata), 0);|hid_report_raw_event(hdev, HID_INPUT_REPORT, xdata, sizeof(xdata), sizeof(xdata), 0);|g' driver/razerkbd_driver.c
          '';
        });
      });
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
