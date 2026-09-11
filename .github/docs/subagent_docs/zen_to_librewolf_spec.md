# Zen Browser → LibreWolf Replacement — Spec

## Current State Analysis

Zen Browser is installed exclusively via Flatpak (app ID `app.zen_browser.zen`),
listed once as a default app in `modules/flatpak.nix`, and referenced as a
pinned/favourite dock app in six places that must stay in sync:

| File | Role | Reference |
|---|---|---|
| `modules/flatpak.nix` | all roles (`defaultApps`) | `"app.zen_browser.zen"` |
| `home/noctalia.nix` | Hyprland desktop, active shell | `basePinnedApps` → `"app.zen_browser.zen"` (used for both `launcher.pinned` and `dock.pinned`) |
| `home/dank-material-shell.nix` | Hyprland desktop, disabled shell (kept in sync with Noctalia per its own comment) | `basePinnedApps` → `"app.zen_browser.zen"` |
| `modules/gnome-desktop.nix` | GNOME desktop role | `favorite-apps` → `"app.zen_browser.zen.desktop"` |
| `modules/gnome-htpc.nix` | GNOME htpc role | `favorite-apps` → `"app.zen_browser.zen.desktop"` |
| `modules/gnome-server.nix` | GNOME server role | `favorite-apps` → `"app.zen_browser.zen.desktop"` |
| `modules/gnome-stateless.nix` | GNOME stateless role | `favorite-apps` → `"app.zen_browser.zen.desktop"` |

Two comment-only references exist (`home-desktop.nix:141`, `home-htpc.nix:162`)
documenting `MOZ_ENABLE_WAYLAND`, worded "forces Firefox/Zen to use the Wayland
backend." LibreWolf is also a Gecko/Firefox-derived browser and is affected by
the same variable, so the comment wording should be updated to stay accurate.

False positives (no change — unrelated to Zen Browser):
- `modules/gaming.nix` — "Ryzen" (AMD Zen microarchitecture, CPU pinning comment)
- `modules/system-gaming.nix` — "zen 6.12+" (Linux-Zen kernel scheduler reference)
- `home/gnome-common-browser.nix` — "zenity" (GNOME dialog utility)

Archival spec/review docs under `.github/docs/subagent_docs/` that happen to
mention "zen" (kernel/Ryzen contexts, matched by the same broad grep) are
historical records of past work and are out of scope — they are not edited
retroactively.

## Problem Definition

Replace Zen Browser with LibreWolf across the Flatpak install list and every
dock/favourites pin, without introducing a new installation mechanism.

## Proposed Solution

Swap the Flatpak app ID `app.zen_browser.zen` → `io.gitlab.librewolf-community`
(LibreWolf's official Flathub ID, confirmed via Flathub listing at
https://flathub.org/en/apps/io.gitlab.librewolf-community) everywhere it
appears — install list and all six dock/favourites references — plus the two
comment updates. No structural change: LibreWolf installs through the same
`modules/flatpak.nix` first-boot service Zen used, and slots into the same
`basePinnedApps` / `favorite-apps` list positions.

## Implementation Steps (Option B pattern — no structural changes)

This is a pure value substitution within existing files; it does not touch the
Module Architecture Pattern (no new `lib.mkIf`, no new files, no role
reclassification).

1. `modules/flatpak.nix` — `defaultApps` list: replace `"app.zen_browser.zen"`
   with `"io.gitlab.librewolf-community"`.
2. `home/noctalia.nix` — `basePinnedApps`: same substitution (affects both
   launcher pins and dock pins, since both reference the same list).
3. `home/dank-material-shell.nix` — `basePinnedApps`: same substitution, to
   preserve the deliberate DMS/Noctalia dock-parity noted in both files'
   comments.
4. `modules/gnome-desktop.nix` — `favorite-apps`: replace
   `"app.zen_browser.zen.desktop"` with `"io.gitlab.librewolf-community.desktop"`.
5. `modules/gnome-htpc.nix` — same substitution in `favorite-apps`.
6. `modules/gnome-server.nix` — same substitution in `favorite-apps`.
7. `modules/gnome-stateless.nix` — same substitution in `favorite-apps`
   (list also contains `torbrowser.desktop`, unaffected).
8. `home-desktop.nix` — update comment "forces Firefox/Zen to use the Wayland
   backend" → "forces Firefox/LibreWolf to use the Wayland backend".
9. `home-htpc.nix` — same comment update.

Existing installs: the `flatpak-install-apps` systemd service in
`modules/flatpak.nix` already uninstalls any Flatpak no longer present in
`appsToInstall` only if it was tracked via `excludeApps`/`managedApps` — Zen
was a plain `defaultApps` entry, not managed/excluded, so removing it from the
list does **not** trigger automatic uninstall on existing hosts (this mirrors
existing behavior for any `defaultApps` removal in this repo; no new gap is
introduced). This is a pre-existing, accepted limitation of the flatpak
module, not something this change needs to solve. Out of scope.

## Dependencies

None (no new flake inputs; LibreWolf ships from the existing Flathub remote
already configured by `modules/flatpak.nix`). Context7 lookup not applicable —
Flathub app IDs are not covered by Context7 library docs; verified instead via
the Flathub listing directly (see Proposed Solution).

## Configuration Changes

None beyond the app-ID substitutions listed above. No new options, no
`system.stateVersion` change, no new flake inputs.

## Risks and Mitigations

- **Risk:** Typo in the new Flatpak ID silently fails the flatpak-install
  service (it warns and retries next boot, does not fail the NixOS build).
  **Mitigation:** ID verified against the live Flathub listing before use.
- **Risk:** Missing one of the seven reference sites leaves a stale Zen pin.
  **Mitigation:** Full-repo grep for `zen` (case-insensitive, `*.nix`) enumerated
  all sites in Phase 1; Phase 3 review re-greps to confirm zero remaining
  `app.zen_browser` references outside archival docs.
- **Risk:** `home/dank-material-shell.nix` is currently disabled
  (`enable = false`) — easy to skip since it's dormant.
  **Mitigation:** Explicitly included in scope (step 3) since the file's own
  comments document it as intentionally kept in sync with the active shell for
  a future one-line revert.
