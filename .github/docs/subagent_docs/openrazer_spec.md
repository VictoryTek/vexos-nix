# OpenRazer Desktop Support — Specification

**Feature:** `openrazer`
**Target Role:** Desktop only
**Date:** 2026-05-07
**Status:** DRAFT

---

## 1. Current State Analysis

### 1.1 User Definition

`modules/users.nix` defines the single primary user:

```nix
users.users.nimda = {
  isNormalUser = true;
  description  = "nimda";
  extraGroups  = [
    "wheel"
    "networkmanager"
  ];
};
```

Role-specific groups are appended by service modules via NixOS list merging
(e.g. `modules/audio.nix` adds `"audio"` via `users.users.nimda.extraGroups = [ "audio" ]`).

### 1.2 Desktop Configuration

`configuration-desktop.nix` expresses its role through an import list. It currently
imports 24 modules. There is no existing Razer-related module anywhere in the repo.

### 1.3 Relevant Module Patterns

- `modules/asus.nix` — clean hardware peripheral module, no `lib.mkIf` guards,
  unconditionally applies when imported.
- `modules/gaming.nix` — appends user groups via `users.users.nimda.extraGroups`.
- `modules/audio.nix` — uses `users.users.nimda.extraGroups = [ "audio" ]` to
  append a group without touching `modules/users.nix`.

### 1.4 No Existing Razer Support

No openrazer module, no `hardware.openrazer` config, no `plugdev` / `openrazer`
group, and no polychromatic / razergenie package anywhere in the project.

---

## 2. Problem Definition

The user has Razer peripherals (keyboards, mice, and/or headsets) that require
the OpenRazer kernel drivers and userspace daemon on Linux. Without this:

- Razer devices work as generic HID devices only (no RGB control, no DPI configuration,
  no battery notifications for wireless devices).
- No GUI is available to configure lighting effects or device settings.

The feature should be desktop-only; server, headless-server, htpc, and stateless
roles do not need Razer peripheral management.

---

## 3. Research Summary

### 3.1 Sources

1. **nixpkgs openrazer module** —
   `github:NixOS/nixpkgs/master/nixos/modules/hardware/openrazer.nix`
   (authoritative; read raw source)

2. **NixOS Options search** — `hardware.openrazer.*` options confirmed present
   in nixos-25.11, 10 options total.

3. **polychromatic package** — `pkgs.polychromatic` v0.9.3 confirmed in
   nixos-25.11. GTK-based GUI frontend for OpenRazer.

4. **razergenie package** — `pkgs.razergenie` v1.3.0 confirmed in nixos-25.11.
   Qt-based GUI alternative.

5. **polychromatic.app** — Official docs confirm polychromatic is a pure
   frontend; it requires the OpenRazer daemon running in userspace.

6. **nixpkgs openrazer module implementation** — The module sets:
   - `boot.extraModulePackages` to `config.boot.kernelPackages.openrazer`
   - `boot.kernelModules` to `["razerkbd" "razermouse" "razerkraken" "razeraccessory"]`
   - `services.udev.packages` for device rules
   - `users.groups.openrazer.members` from `hardware.openrazer.users`
   - A per-user systemd service `openrazer-daemon` (starts with graphical session)

### 3.2 Key Findings

**Kernel module approach:**
NixOS uses out-of-tree DKMS-style modules packaged as `pkgs.linuxPackages.openrazer`
(accessed via `config.boot.kernelPackages.openrazer`). The NixOS module handles
`boot.extraModulePackages` and `boot.kernelModules` automatically when
`hardware.openrazer.enable = true`. No manual kernel module configuration needed.

**User group:**
Users must belong to the `openrazer` group (not `plugdev`) to communicate with
the daemon via D-Bus. The canonical way to achieve this in NixOS is via:
```nix
hardware.openrazer.users = [ "nimda" ];
```
This is preferred over `users.users.nimda.extraGroups = [ "openrazer" ]` because
the option is co-located with the hardware configuration and is the pattern
documented in the nixpkgs module.

**Daemon lifecycle:**
`openrazer-daemon` runs as a **user-level systemd service** (not system-level).
It is wired to `graphical-session.target`, so it starts automatically when the
user's GNOME session starts. No manual service activation is needed.

**Screensaver integration:**
`hardware.openrazer.devicesOffOnScreensaver = true` (the default) requires the
daemon to detect screensaver activation via D-Bus. This works correctly with
GDM/GNOME on NixOS.

**GUI tooling:**
- `polychromatic` — recommended. GTK4 + Python, GNOME-friendly, tray applet, per-device
  profiles, animated effects editor. Actively maintained (2016–2026).
- `razergenie` — alternative. Qt-based, simpler UI. Suitable as a secondary option.

**NixOS-specific gotchas:**
1. The kernel module is rebuilt per kernel version. After a kernel upgrade, a
   `nixos-rebuild switch` regenerates the module. This is transparent to the user.
2. The daemon is a user service; it will not appear under `systemctl status` —
   use `systemctl --user status openrazer-daemon`.
3. `hardware.openrazer.enable = true` does NOT add users automatically; the
   `hardware.openrazer.users` option must be set explicitly.
4. No new flake inputs are required — openrazer support is fully in nixpkgs.

---

## 4. Proposed Solution Architecture

### 4.1 Module Architecture

Following **Option B** (common base + role additions):

- **New file:** `modules/razer.nix`
  - Imported unconditionally by `configuration-desktop.nix` only.
  - Contains `hardware.openrazer` config + polychromatic GUI package.
  - No `lib.mkIf` guards.
- **Modified file:** `configuration-desktop.nix`
  - Add `./modules/razer.nix` to the imports list.

No changes to `modules/users.nix`, `flake.nix`, or any other role configuration file.

### 4.2 File: `modules/razer.nix` — Full Intended Content

```nix
# modules/razer.nix
# OpenRazer kernel drivers and userspace daemon for Razer peripheral support.
# Provides RGB lighting control, DPI configuration, battery notifications,
# and device profiles via the polychromatic GUI.
#
# Desktop role only: do NOT import in server, headless-server, htpc, or stateless.
#
# Kernel modules (razerkbd, razermouse, razerkraken, razeraccessory) are loaded
# automatically by this module via hardware.openrazer.enable.
# The openrazer-daemon runs as a user-level systemd service tied to the GNOME
# graphical session — no manual service management required.
{ ... }:
{
  # ── OpenRazer drivers and daemon ──────────────────────────────────────────
  hardware.openrazer = {
    enable = true;

    # Add the primary user to the openrazer group.
    # Required for D-Bus access to the daemon.
    users = [ "nimda" ];

    # Sync lighting effects across all connected Razer devices (default: true).
    syncEffectsEnabled = true;

    # Turn off device LEDs when the screensaver activates (default: true).
    devicesOffOnScreensaver = true;
  };

  # ── GUI: polychromatic ────────────────────────────────────────────────────
  # GTK4 frontend for OpenRazer: lighting effects editor, tray applet,
  # per-device profiles. Preferred over razergenie for GNOME desktops.
  environment.systemPackages = with pkgs; [
    polychromatic
  ];
}
```

> **Note on `pkgs` binding:** Since this module has `{ ... }:` as its argument
> signature, the implementation subagent must change this to `{ pkgs, ... }:`
> to make `pkgs` available for `environment.systemPackages`.

### 4.3 Modified File: `configuration-desktop.nix`

Add `./modules/razer.nix` to the imports list. Insert it after the
`./modules/users.nix` line (last import) to maintain logical grouping:

```nix
  imports = [
    # ... existing imports ...
    ./modules/locale.nix
    ./modules/users.nix
    ./modules/razer.nix          # ← ADD THIS LINE
  ];
```

No other changes to `configuration-desktop.nix`.

---

## 5. Implementation Steps

1. Create `modules/razer.nix` with the content specified in §4.2.
2. Add `./modules/razer.nix` to the imports list in `configuration-desktop.nix`
   after `./modules/users.nix`.
3. No changes to any other file.

---

## 6. User Group Requirements

| Group | Purpose | How assigned |
|-------|---------|--------------|
| `openrazer` | D-Bus access to openrazer-daemon | `hardware.openrazer.users = [ "nimda" ]` |

The `openrazer` group is created automatically by `hardware.openrazer.enable = true`.
No `plugdev` group membership is required on NixOS (differs from Arch/Ubuntu installs).

---

## 7. Packages

| Package | Version (25.11) | Purpose | Selected |
|---------|----------------|---------|---------|
| `polychromatic` | 0.9.3 | GTK4 GUI: lighting effects, tray applet, profiles | ✓ Primary |
| `razergenie` | 1.3.0 | Qt GUI: simpler device configuration | ✗ Alternative |

`polychromatic` is selected as the primary GUI because:
- GTK4/libadwaita styling integrates well with GNOME
- Richer feature set (animated effects, per-device profiles, tray applet)
- Actively maintained through 2026
- More complete device support (mirrors full OpenRazer device list)

---

## 8. Kernel Module Considerations

- The NixOS `hardware.openrazer` module automatically sets:
  - `boot.extraModulePackages = [ config.boot.kernelPackages.openrazer ]`
  - `boot.kernelModules = [ "razerkbd" "razermouse" "razerkraken" "razeraccessory" ]`
- This project uses `boot.kernelPackages = pkgs.linuxPackages_latest` (set in
  `modules/system.nix`). The `kernelPackages.openrazer` attribute resolves
  correctly for `linuxPackages_latest`.
- After a kernel version bump, `nixos-rebuild switch` will rebuild the out-of-tree
  module automatically via the Nix build system. No user action required.
- No DKMS daemon is used on NixOS; rebuilds happen at switch time.

---

## 9. Risks and Mitigations

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| Razer device not yet supported by openrazer | Low | User can check the OpenRazer device list at openrazer.github.io/supported-devices |
| Kernel module build failure on very new kernel | Low | `linuxPackages_latest.openrazer` is kept up to date in nixpkgs; if broken, pin to `linuxPackages` (LTS) |
| openrazer-daemon fails to start | Low | D-Bus session must be running; GNOME starts it automatically. Debug with `systemctl --user status openrazer-daemon` |
| Conflict with other kernel modules | Very Low | Razer modules are device-specific and do not conflict with common GPU or input drivers |
| `nix flake check` failure due to missing `pkgs` in module arg | Low | Use `{ pkgs, ... }:` as module argument signature |

---

## 10. Files Changed

| File | Action |
|------|--------|
| `modules/razer.nix` | CREATE |
| `configuration-desktop.nix` | MODIFY — add one import line |

**No changes to:**
- `flake.nix` (no new inputs needed)
- `modules/users.nix` (group added via `hardware.openrazer.users`, not extraGroups)
- Any server, htpc, stateless, or headless-server configuration file
