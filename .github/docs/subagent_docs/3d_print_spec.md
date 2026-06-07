# Spec: modules/3d-print.nix

## Phase 1: Research & Specification

### Current State Analysis

The project uses a well-established pattern for role-specific Flatpak apps:

- `modules/flatpak.nix` — universal base; declares `vexos.flatpak.extraApps` (listOf string,
  merge-concatenated) and runs the first-boot install service.
- `modules/flatpak-desktop.nix` — desktop-role additions via `vexos.flatpak.extraApps`;
  imported only by `configuration-desktop.nix`.
- `configuration-desktop.nix` — import list defines the desktop role; currently imports
  `flatpak.nix` and `flatpak-desktop.nix`.

### Problem Definition

No dedicated module exists for 3D-printing software. The user wants Blender and OrcaSlicer
installed on desktop roles via Flatpak.

### Proposed Solution Architecture

Create `modules/3d-print.nix` following the "Common base + role additions" pattern:
- The file contains only the `vexos.flatpak.extraApps` additions for 3D printing.
- No `lib.mkIf` guards — the import list expresses role membership.
- Import it from `configuration-desktop.nix` only.

### Flatpak App IDs (verified on Flathub)

| App | Flathub ID |
|-----|-----------|
| Blender | `org.blender.Blender` |
| OrcaSlicer | `com.orcaslicer.OrcaSlicer` |

### Implementation Steps

1. Create `modules/3d-print.nix` with `vexos.flatpak.extraApps` listing both app IDs.
2. Add `./modules/3d-print.nix` to the imports list in `configuration-desktop.nix`.

### Files to Modify

- **New:** `modules/3d-print.nix`
- **Modified:** `configuration-desktop.nix`

### Build / Test Commands (Phase 3)

- `nix flake show` — validate flake structure (safe, low RAM)
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd`
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia`
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm`

RAM cost: per-target dry-builds only; no parallel evaluation. SAFE.

### Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| `vexos.flatpak.extraApps` not declared when 3d-print.nix is evaluated | `flatpak.nix` is already imported before `3d-print.nix` in the import list; listOf merge is order-independent |
| App IDs change on Flathub | IDs are stable; OrcaSlicer has been `com.orcaslicer.OrcaSlicer` since its Flathub listing |
