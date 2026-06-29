# Spec: Flatpak managed-app cleanup on feature disable

## Problem
`vexos.flatpak.extraApps` uses NixOS list-merge semantics: feature modules
append to the list inside `lib.mkIf cfg.enable`. When a feature is disabled
the apps are dropped from `extraApps`, but the `flatpak-install-apps` service
only installs and excludes — it never removes apps that were previously
installed by a now-disabled feature. Affected modules: `gaming.nix`
(Lutris, ProtonPlus, PrismLauncher) and `3d-print.nix` (Blender, OrcaSlicer).

## Solution
Add `vexos.flatpak.managedApps` — a list of Flatpak IDs "owned" by feature
modules. Feature modules register their IDs **unconditionally** (outside
`lib.mkIf cfg.enable`). The service removes any managed app that is absent
from `appsToInstall` when the hash stamp changes.

## Implementation steps (Option B — no new files)

1. **`modules/flatpak.nix`**
   - Add `options.vexos.flatpak.managedApps` (`listOf str`, default `[]`)
   - Include `managedApps` in `appsListHash` so service re-runs if managed set changes
   - Add removal step after excluded-apps removal: for each managed app not in
     `appsToInstall`, call `flatpak uninstall` if currently installed

2. **`modules/gaming.nix`**
   - Unconditionally (outside `lib.mkIf cfg.enable`) set `vexos.flatpak.managedApps`
     to the three gaming Flatpak IDs

3. **`modules/3d-print.nix`**
   - Same pattern for Blender and OrcaSlicer

## Why managedApps, not excludeApps
`excludeApps` was designed to prevent default apps from being installed. Reusing
it for feature cleanup would conflate two unrelated concerns and pollute the hash
with apps that should only be excluded on specific roles.

## Risks / mitigations
- Managed apps list is static per module, so removing from `managedApps` AND
  from `extraApps` at the same time would still trigger cleanup (hash changes
  because `appsToInstall` changed).
- User-manually-installed Flatpak apps that happen to match a managed ID would
  be uninstalled — acceptable; all managed IDs are feature-owned, not personal.
