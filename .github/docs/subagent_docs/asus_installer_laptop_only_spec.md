# asus_installer_laptop_only — Spec

## Current State

`scripts/install.sh` and `scripts/stateless-setup.sh` enable
`vexos.hardware.asus.enable = true` on any ASUS ROG/TUF device, including
non-laptops. The non-laptop branch (install.sh:321, stateless-setup.sh:344)
patches `/etc/nixos/flake.nix` with `vexos.hardware.asus.enable = true;`
even though asusd/supergfxd/asusctl are laptop-only tools.

## Problem

`vexos.hardware.asus.enable = true` enables `asusd`, `supergfxd`, and `asusctl`:

- `asusd` requires ASUS WMI/ACPI platform interfaces absent on desktop motherboards
- `supergfxd` manages iGPU↔dGPU MUX switching — a laptop-only feature
- `asusctl aura` controls keyboard/laptop RGB via asusd — not applicable to desktops

On a desktop with an ASUS motherboard, `asus-aura-init.service` fails on every
vexos-update because `asusctl aura effect static -c ffffff` has no working
D-Bus endpoint. The right tool for ASUS desktop Aura RGB is **OpenRGB**, which
controls RGB over USB/i2c.

## Proposed Solution

Split the non-laptop ASUS path to use `programs.openrgb.enable = true` instead:

- ASUS device + **laptop** → `vexos.hardware.asus.enable = true; vexos.hardware.asus.batteryChargeLimit = 80;` (unchanged)
- ASUS device + **desktop** → `programs.openrgb.enable = true;` (new)

`programs.openrgb` is a NixOS option that installs OpenRGB, loads `i2c-dev` and
related kernel modules, and sets up udev rules for USB access.

Update the installer prompt text to describe both outcomes.
Update `modules/asus-opt.nix` header to clarify it is laptop-only.

No new flake inputs. No new tracked modules. The desktop path patches
`hardwareModule` in `/etc/nixos/flake.nix`, same as the laptop path.

## Files to Change

- `scripts/install.sh` — replace non-laptop asus branch with openrgb patch
- `scripts/stateless-setup.sh` — same fix (parallel structure)
- `modules/asus-opt.nix` — update header comment to say "laptop hardware only"

## Fix for Existing Desktop Install

The desktop's `/etc/nixos/flake.nix` has `vexos.hardware.asus.enable = true;`
in its `hardwareModule`. The user must manually change that line to
`programs.openrgb.enable = true;` and run `just switch` on the desktop.
This code fix only prevents recurrence on new installs.
