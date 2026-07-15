# Joplin Client on All DE Roles — Spec

## Current State Analysis

Joplin desktop client (`net.cozic.joplin_desktop`, Flatpak) is currently installed
only on the `desktop` role:

- `modules/flatpak-desktop.nix:12` — adds the app ID via `vexos.flatpak.extraApps`,
  a desktop-role-only addition file imported solely by `configuration-desktop.nix:15`.
- `modules/gnome-desktop.nix:100` — lists `net.cozic.joplin_desktop.desktop` in the
  GNOME "Office" app-folder for the desktop role only.
- `home-desktop.nix:226` — mirrors the same app-folder entry in the desktop-role
  home-manager app-folder init script (`vexos-init-app-folders-desktop`).

Roles with a GNOME desktop environment: `desktop`, `stateless`, `htpc`, `server`
(all import `modules/gnome.nix` + a role addition, and all four import
`modules/flatpak.nix`), plus `vanilla` (GNOME via `services.desktopManager.gnome.enable`
directly, no `modules/gnome.nix`, and **no Flatpak module at all** — by design, per its
file header: "Does NOT include: ... Flatpak"). `headless-server` has no DE
(`services.xserver.enable = lib.mkForce false`).

User has confirmed: exclude `vanilla` (preserve its Flatpak-free stock-baseline design).
Target roles: **desktop, stateless, htpc, server**.

`modules/flatpak.nix` is the shared base module imported by exactly these four roles
(`configuration-desktop.nix`, `configuration-stateless.nix`, `configuration-htpc.nix`,
`configuration-server.nix`) and by no others — its `defaultApps` list (line 5-16) is
already the base-module mechanism for "installed on every display role that imports
flatpak.nix," per the file's own header comment.

Each of the four roles also has a GNOME "Office" app-folder defined in its own
`gnome-<role>.nix` (or `home-desktop.nix` for desktop's belt-and-suspenders dconf
init script), none of which currently list Joplin except desktop's two.

## Problem Definition

Joplin client should be installed via Flatpak, and surfaced in the GNOME "Office"
app-folder, on every role that has both a GNOME DE and Flatpak support — not just
`desktop`.

## Proposed Solution

1. **Flatpak install list** — move `"net.cozic.joplin_desktop"` from
   `modules/flatpak-desktop.nix`'s `extraApps` (desktop-only) into
   `modules/flatpak.nix`'s `defaultApps` (shared base, all four target roles).
   This is a correct use of the existing Option B base-module mechanism: `flatpak.nix`
   is only ever imported by the four target roles, so adding to `defaultApps` there
   installs it exactly on desktop, stateless, htpc, and server, and nowhere else.
   No `excludeApps` entry currently blocks `net.cozic.joplin_desktop` on any of the
   three other roles (checked all three roles' `vexos.flatpak.excludeApps` lists).

2. **GNOME app-folder entries** — add `"net.cozic.joplin_desktop.desktop"` to the
   Office folder's `apps` list in:
   - `modules/gnome-stateless.nix` (Office apps currently: `org.onlyoffice.desktopeditors.desktop`, `org.gnome.TextEditor.desktop`)
   - `modules/gnome-htpc.nix` (Office apps currently: `org.gnome.TextEditor.desktop`)
   - `modules/gnome-server.nix` (Office apps currently: `org.gnome.TextEditor.desktop`)

   `modules/gnome-desktop.nix:100` and `home-desktop.nix:226` already list it —
   no change needed there.

## Implementation Steps (Option B compliant)

1. `modules/flatpak-desktop.nix` — remove the `"net.cozic.joplin_desktop"` line
   (and its comment) from `extraApps`. This file remains desktop-only additions.
2. `modules/flatpak.nix` — add `"net.cozic.joplin_desktop"` to `defaultApps`
   (shared base, applies to all four importing roles).
3. `modules/gnome-stateless.nix` — add `"net.cozic.joplin_desktop.desktop"` to the
   Office folder `apps` list.
4. `modules/gnome-htpc.nix` — add `"net.cozic.joplin_desktop.desktop"` to the
   Office folder `apps` list.
5. `modules/gnome-server.nix` — add `"net.cozic.joplin_desktop.desktop"` to the
   Office folder `apps` list.

No new dependencies, no Context7 lookup needed (internal Nix module change only,
no new external library/flake input).

## Configuration Changes

None beyond the module edits above. No new options introduced.

## Risks and Mitigations

- **Risk:** `flatpak.nix`'s `appsListHash` changes for all four roles, which triggers
  the `flatpak-install-apps` systemd service to re-run and reconcile on next
  `nixos-rebuild switch` for those hosts. This is expected/intended behavior (same
  mechanism used for every `defaultApps` change) — not a regression.
- **Risk:** None of the three roles' `excludeApps` lists currently block Joplin, so no
  unwanted suppression. Verified by reading `configuration-stateless.nix`,
  `configuration-htpc.nix`, `configuration-server.nix` `excludeApps` blocks.
- **Risk:** `vanilla` role is explicitly out of scope per user confirmation — no changes
  to `configuration-vanilla.nix`.
