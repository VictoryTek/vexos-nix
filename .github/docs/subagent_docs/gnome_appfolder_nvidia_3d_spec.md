# GNOME App Folder Additions: nvidia-settings + 3D Folder

## Phase 1: Research & Specification

### Current State Analysis

`home-desktop.nix` contains `vexos-init-app-folders` — a oneshot systemd user service
that writes GNOME app folder configuration via `dconf write` on first login. A stamp file
(`~/.local/share/vexos/.dconf-app-folders-initialized-v2`) prevents re-runs, preserving
user customizations after the initial setup.

Current folder structure:
- `Games` — game launchers
- `Game Utilities` — ProtonPlus, Vesktop, Discord, etc.
- `Office` — OnlyOffice, TextEditor, Papers
- `Utilities` — ExtensionManager, GearLever, Tweaks, Warehouse, MissionCenter, Flatseal, PikaBackup
- `System` — pavucontrol, ROG control, Settings, Seahorse, etc.

### Problem Definition

Two additions are needed:

1. **nvidia-settings.desktop → Utilities folder**: The `nvidia-settings` GUI is installed
   only on nvidia GPU variants (via `hardware.nvidia.*` in `modules/gpu/nvidia.nix`). It
   should appear in the Utilities folder for easy access on nvidia builds.

2. **New `3D` folder**: `modules/3d-print.nix` installs Blender and OrcaSlicer via Flatpak
   on the desktop role. These have no natural home in the existing folders. A dedicated `3D`
   folder improves discoverability.

### Research Findings

**GNOME dconf app-folder schema:**
- `folder-children`: GLib Variant string list of folder IDs
- `folders/<ID>/name`: Display name (localised string)
- `folders/<ID>/apps`: GLib Variant string list of .desktop file IDs
- Missing .desktop IDs are silently ignored by GNOME Shell — entries for apps not
  installed on the current system are safe to include unconditionally

**nvidia-settings on NixOS:**
- Installed as part of `hardware.nvidia.package` (all variants: latest, legacy_535, legacy_470)
- Provides `nvidia-settings.desktop` in the system application directory
- Not present on amd/intel/vm GPU variants

**3d-print.nix scope:**
- `modules/3d-print.nix` is imported unconditionally in `configuration-desktop.nix` (line 13)
- All desktop GPU variants (amd, nvidia, intel, vm) have Blender and OrcaSlicer in extraApps
- A 3D folder is therefore valid for all desktop variants

### Proposed Solution

**Single change to `home-desktop.nix`:**

1. Bump stamp from `-v2` to `-v3` so existing users receive the new defaults on next login
2. Add `'3D'` to `folder-children`
3. Add `3D` folder definition with `org.blender.Blender.desktop` and
   `com.orcaslicer.OrcaSlicer.desktop`
4. Add `'nvidia-settings.desktop'` to the Utilities folder app list unconditionally
   — GNOME silently ignores it on non-nvidia variants where the .desktop file does not exist

**Why unconditional nvidia-settings entry:**
- GNOME Shell only shows entries in app folders when the corresponding .desktop file
  exists on the system. An entry for a non-existent .desktop is a no-op — no visual
  artefact, no error.
- This avoids the complexity of a separate systemd service, a build-time `lib.mkIf`,
  or reading/modifying the dconf list at runtime.
- Prior art: the `System` folder already lists `rog-control-center.desktop` which is
  only present on ASUS hardware.

### Implementation Steps

1. Edit `home-desktop.nix` — `vexos-init-app-folders` service `ExecStart` script:
   a. Change stamp variable to `dconf-app-folders-initialized-v3`
   b. Add `'3D'` to the `folder-children` list
   c. Add the `3D` folder `name` and `apps` dconf writes after the `Office` block
   d. Add `'nvidia-settings.desktop'` to the `Utilities/apps` list

### Dependencies

No new external dependencies. No Context7 lookup required (pure dconf/shell configuration).

### Build/Test Commands (Phase 3)

- `nix flake show` — validate flake structure
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd` — amd variant (no nvidia-settings file)
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia` — nvidia variant (nvidia-settings present)
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm` — vm variant

RAM assessment: per-target dry-build only; safe on 32 GB RAM.

### Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| Stamp bump resets user folder customizations | Expected behaviour; documented in code comment |
| nvidia-settings.desktop entry on non-nvidia builds | GNOME silently ignores unknown .desktop IDs |
| Flatpak apps use App ID without `.desktop` suffix | dconf apps list requires the `.desktop` suffix; Blender app ID is `org.blender.Blender`, so entry is `org.blender.Blender.desktop` |
