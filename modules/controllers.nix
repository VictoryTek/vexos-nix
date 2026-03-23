# modules/controllers.nix
# Gamepad and controller support: Xbox (xone/xpadneo), Nintendo Switch,
# Sony DualShock/DualSense, Steam hardware, generic HID udev rules.
{ config, pkgs, lib, ... }:
{
  # ── Xbox controllers ──────────────────────────────────────────────────────
  # xone: Xbox One / Series S|X USB dongle and wired controllers
  hardware.xone.enable = true;

  # xpadneo: Xbox wireless controllers via Bluetooth
  hardware.xpadneo.enable = true;

  # ── Nintendo Switch Pro Controller / Joy-Cons ─────────────────────────────
  # hid_nintendo is an in-kernel driver; no NixOS wrapper option exists in 24.11.
  boot.kernelModules = [ "hid_nintendo" "hid_sony" ];

  # ── udev rules ────────────────────────────────────────────────────────────
  services.udev.extraRules = ''
    # ── Sony DualShock 4 (USB) ──
    KERNEL=="hidraw*", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="05c4", MODE="0660", GROUP="input"
    KERNEL=="hidraw*", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="09cc", MODE="0660", GROUP="input"
    # ── Sony DualSense (USB) ──
    KERNEL=="hidraw*", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="0ce6", MODE="0660", GROUP="input"
    # ── Sony DualSense Edge (USB) ──
    KERNEL=="hidraw*", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="0df2", MODE="0660", GROUP="input"
    # ── Sony controllers via Bluetooth ──
    KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="054c", MODE="0660", GROUP="input"

    # ── 8BitDo Ultimate Bluetooth ──
    SUBSYSTEM=="input", ATTRS{idVendor}=="2dc8", ATTRS{idProduct}=="3106", MODE="0660", GROUP="input"

    # ── Generic: allow all input devices for the input group ──
    SUBSYSTEM=="input", MODE="0660", GROUP="input"
  '';

  # Note: user nimda must be in the "input" group (set via extraGroups in configuration.nix).
}
