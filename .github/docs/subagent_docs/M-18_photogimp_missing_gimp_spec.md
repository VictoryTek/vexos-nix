# M-18 — PhotoGIMP launcher ships without GIMP itself installed

Status: Phase 1 (Research & Specification)
Source: MASTER_PLAN M-18 (BUGS M17) · `home-desktop.nix`, `home/photogimp.nix`

## Current State

`home/photogimp.nix` (imported by `home-desktop.nix`, `photogimp.enable = true`) only
overlays PhotoGIMP's Photoshop-style branding/config on top of GIMP — it assumes GIMP
is already installed (its own header: "Works with: GIMP 3.0 installed via Flatpak
(org.gimp.GIMP)"). Repo-wide grep across every Flatpak install list
(`modules/flatpak.nix`, `modules/flatpak-desktop.nix`, `home-desktop.nix`) confirms
`org.gimp.GIMP` appears nowhere — the desktop role's declarative Flatpak list never
installs GIMP itself. Confirmed with the user this is real (not a stale MASTER_PLAN
claim): it currently works on their machine only because GIMP was installed
independently of this repo's declarative management at some point, and Flatpak app
installs persist across rebuilds regardless of the declarative list. A fresh desktop
install would get PhotoGIMP's launcher/config pointing at a Flatpak app that was never
installed.

`home-stateless.nix` already deliberately excludes GIMP from stateless (documented
inline, `photogimp.nix` isn't even imported there) — unaffected by this fix.

## Problem Definition

Ensure GIMP is actually installed wherever PhotoGIMP's overlay is applied.

## Proposed Solution

Add `"org.gimp.GIMP"` to `modules/flatpak-desktop.nix`'s `extraApps` list — the exact
file already scoped to the desktop role (matching `photogimp.nix`'s own scope) and
already the established place for desktop-only Flatpak additions.

## Implementation Steps

1. `modules/flatpak-desktop.nix` — add `"org.gimp.GIMP"` to `extraApps`.

## Configuration Changes

None.

## Risks and Mitigations

- **None** — purely additive to an existing list-merge option
  (`vexos.flatpak.extraApps`), scoped to the same role PhotoGIMP already targets.
