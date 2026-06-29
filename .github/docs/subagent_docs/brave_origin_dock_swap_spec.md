# Brave Origin Dock & Default Browser Swap — Spec

## Current State Analysis

- `modules/gnome-desktop.nix:25` sets the GNOME `favorite-apps` dconf key
  (desktop role only) and currently pins `brave-browser.desktop` (regular
  Brave) as the second dock entry.
- `home/gnome-common.nix:61-70` declares `xdg.mimeApps.defaultApplications`,
  registering `brave-browser.desktop` as the default handler for
  `x-scheme-handler/http(s)`, `text/html`, `application/xhtml+xml`, and
  `x-scheme-handler/ftp`. This file is **shared** — imported by
  `home-desktop.nix`, `home-htpc.nix`, `home-stateless.nix`, and
  `home-server.nix`.
- `vexos.brave-origin` (built in `pkgs/brave-origin/default.nix`, exposing
  `brave-origin.desktop`) is only installed on the desktop role, via
  `modules/packages-desktop.nix:8`. It is not present on htpc, stateless, or
  server roles.

## Problem

The user wants Brave Origin to replace regular Brave as both the GNOME dock
favorite and the default browser, on desktop. Because the MIME default is
declared in a file shared across four roles, but `brave-origin` is only
packaged for one of them, the MIME change cannot be made directly in
`home/gnome-common.nix` without breaking default-browser resolution on
htpc/stateless/server (pointing at a `.desktop` file that doesn't exist on
those systems).

## Decision (confirmed with user)

- Dock favorite: desktop-role only, edited in place — safe, no module split
  needed since `gnome-desktop.nix` is already a desktop-only addition file.
- Default browser MIME association: scope to desktop only. Per the Module
  Architecture Pattern (Option B), the shared `home/gnome-common.nix` must
  not gain a role-conditional inside it. Instead:
  - Remove the `xdg.mimeApps` block from `home/gnome-common.nix` (it becomes
    role-agnostic again — no MIME default declared there).
  - Add a new desktop-only file `home/gnome-common-desktop.nix` containing
    the `xdg.mimeApps` block, pointed at `brave-origin.desktop`.
  - Import `./home/gnome-common-desktop.nix` from `home-desktop.nix` only.
  - htpc/server/stateless roles lose the declarative default-browser MIME
    association entirely (previously pointed at `brave-browser.desktop`,
    which is still installed there via `packages-common.nix`, but is no
    longer declared as XDG default). This is an accepted, explicit scope
    reduction — those roles will fall back to GNOME's normal MIME
    resolution / first-run prompt for browser selection.

## Implementation Steps

1. `modules/gnome-desktop.nix`: change `favorite-apps` entry
   `"brave-browser.desktop"` → `"brave-origin.desktop"`.
2. `home/gnome-common.nix`: delete the `xdg.mimeApps` / `xdg.configFile."mimeapps.list".force`
   / `xdg.dataFile."applications/mimeapps.list".force` block and its
   preceding comment.
3. New file `home/gnome-common-desktop.nix`: desktop-only addition containing
   the same `xdg.mimeApps` block, with `brave-origin.desktop` in place of
   `brave-browser.desktop`.
4. `home-desktop.nix`: add `./home/gnome-common-desktop.nix` to `imports`.

## Dependencies

None — no new external library or flake input. Context7 verification not
required (internal-only Home Manager option change).

## Risks & Mitigations

- **Risk:** htpc/stateless/server roles silently lose declarative default
  browser MIME registration. **Mitigation:** explicitly called out above;
  accepted by user as in-scope tradeoff for the "desktop role only" choice.
- **Risk:** `brave-origin.desktop` must exist on the desktop role's system
  closure for both the dock favorite and MIME default to resolve.
  **Mitigation:** already verified — `vexos.brave-origin` is installed via
  `modules/packages-desktop.nix:8`, which only applies to the desktop role,
  matching the scope of both edits.
