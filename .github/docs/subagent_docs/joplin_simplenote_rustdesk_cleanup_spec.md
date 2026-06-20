# Spec: Joplin Office Folder + Simplenote Removal + RustDesk Client Ban

## Current State Analysis

### Change 1 — Add Joplin to Office app-folder (desktop only)
- `net.cozic.joplin_desktop` is already installed as a desktop-role Flatpak via `modules/flatpak-desktop.nix`
- The Office app-folder in `modules/gnome-desktop.nix:72-79` contains:
  `org.onlyoffice.desktopeditors.desktop`, `org.gnome.TextEditor.desktop`, `org.gnome.Papers.desktop`
- Joplin is not present in any Office folder; its desktop file is `net.cozic.joplin_desktop.desktop`
- Other roles (stateless, htpc, server) do not install Joplin; adding it there would be inconsistent

### Change 2 — Remove Simplenote from all roles
- `com.simplenote.Simplenote` is in `defaultApps` in `modules/flatpak.nix:10` (applied to all display roles)
- A dedicated `systemd.services.flatpak-configure-overrides` service exists solely to grant Simplenote Wayland socket access (lines 179-197)
- A large comment block above the service explains the Simplenote Wayland workaround (lines 165-178)
- To uninstall from already-deployed hosts, `com.simplenote.Simplenote` must be added to the globally-banned-apps block in the install script

### Change 3 — Ban RustDesk client Flatpak (`com.rustdesk.RustDesk`)
- Not tracked in any Nix config — was installed manually outside the flake
- The globally-banned-apps block in `modules/flatpak.nix` (currently only `com.github.wwmm.easyeffects`) will unconditionally uninstall it on next boot
- `modules/server/rustdesk.nix` (relay/signal server daemon) is a separate concern and is NOT touched

## Problem Definition
1. Joplin is installed but missing from the Office app-folder in the GNOME app grid
2. Simplenote is broken/non-functional and should be removed from all roles and uninstalled from deployed hosts
3. RustDesk client does not work on Wayland; must be banned and removed from deployed hosts

## Proposed Solution Architecture

### File changes

| File | Change |
|------|--------|
| `modules/gnome-desktop.nix` | Add `"net.cozic.joplin_desktop.desktop"` to Office apps list |
| `modules/flatpak.nix` | Remove Simplenote from defaultApps; add Simplenote + RustDesk to banned block; remove flatpak-configure-overrides service and its comment |

### Implementation steps

1. `modules/gnome-desktop.nix` — add `"net.cozic.joplin_desktop.desktop"` to the Office folder apps list (after `org.gnome.Papers.desktop`)
2. `modules/flatpak.nix`:
   a. Remove `"com.simplenote.Simplenote"` from `defaultApps`
   b. Add `com.simplenote.Simplenote` and `com.rustdesk.RustDesk` to the globally-banned-apps `for app in \` block in the install script
   c. Remove the entire `flatpak-configure-overrides` systemd service block (lines 179-197)
   d. Remove the Simplenote Wayland override comment block (lines 165-178)

## Risks and Mitigations
- **Risk**: Removing `flatpak-configure-overrides` while other overrides may be needed in future — **Mitigation**: The service has no other entries; future overrides can re-add the service
- **Risk**: RustDesk Flatpak app ID differs from `com.rustdesk.RustDesk` — **Mitigation**: This is the canonical Flathub app ID
- **Risk**: Globally banned app uninstall only runs when stamp changes — **Mitigation**: The stamp hash includes `excludeApps`; adding banned apps to the script body (not the option) runs unconditionally every time the stamp changes due to any `appsToInstall`/`excludeApps` change
  - Actually: the banned-apps block runs every time the stamp is missing OR the hash changes. Since we're also removing Simplenote from defaultApps, the hash changes, triggering a full sync run on next boot.
