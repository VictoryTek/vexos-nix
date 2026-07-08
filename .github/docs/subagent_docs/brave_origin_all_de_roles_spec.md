# Brave Origin as Default Browser & Dock Favorite on All DE Roles — Spec

## Current State Analysis

- `modules/packages-desktop.nix` installs both `brave` and `vexos.brave-origin`
  (built in `pkgs/brave-origin/default.nix`) as system packages. It is imported
  by `configuration-desktop.nix`, `configuration-server.nix`,
  `configuration-htpc.nix`, and `configuration-stateless.nix` — i.e. every
  role with a GNOME desktop except `vanilla` and `headless-server`. This
  contradicts the assumption in the earlier `brave_origin_dock_swap_spec.md`
  ("brave-origin is only installed on the desktop role") — `brave-origin` is
  now packaged on all four DE roles, but the dock/default-browser wiring was
  never extended to match.
- Dock favorites (`favorite-apps` dconf key):
  - `modules/gnome-desktop.nix:25` — already `brave-origin.desktop` (done in
    a prior task).
  - `modules/gnome-server.nix:20`, `modules/gnome-htpc.nix:20`,
    `modules/gnome-stateless.nix:20` — still pin `brave-browser.desktop`.
- Default browser (XDG MIME):
  - `home/gnome-common-desktop.nix` declares `xdg.mimeApps.defaultApplications`
    pointing at `brave-origin.desktop` for http(s), html, xhtml, ftp, mailto.
    Imported only by `home-desktop.nix`.
  - `home-server.nix`, `home-htpc.nix`, `home-stateless.nix` import
    `home/gnome-common.nix` but not the desktop-only MIME file, so they have
    **no** declarative default-browser association at all.
- Migration service: `home-desktop.nix` runs a one-shot
  `vexos-migrate-dock-brave-origin` systemd user service that rewrites any
  stale `brave-browser.desktop` entry surviving in the *user* dconf database
  (which shadows the system default) to `brave-origin.desktop`. Server/htpc/
  stateless roles have no equivalent, so existing installs of those roles
  would keep a dead `brave-browser.desktop` dock entry after the dconf
  default changes.
- Roles intentionally excluded from this change:
  - `vanilla` — explicitly a stock NixOS+GNOME baseline
    (`configuration-vanilla.nix` header: "Does NOT include: ... branding, or
    custom packages"). Does not import `packages-desktop.nix`, so
    `brave-origin` is not installed there. Out of scope.
  - `headless-server` — `services.xserver.enable = lib.mkForce false;` in
    `configuration-headless-server.nix`; no GNOME, no dock. Out of scope.

## Problem

Brave Origin should be the default browser and pinned dock favorite (in the
same dock position/style as the desktop role) on every role that actually
ships a GNOME desktop and already installs `brave-origin`: desktop (done),
server, htpc, stateless.

## Proposed Solution

1. **Dock favorite** — in `modules/gnome-server.nix`, `modules/gnome-htpc.nix`,
   `modules/gnome-stateless.nix`, replace the `"brave-browser.desktop"` entry
   in `favorite-apps` with `"brave-origin.desktop"`, in the same list
   position it currently occupies (first entry in each role's list, same as
   desktop).
2. **Default browser MIME association** — generalize the desktop-only MIME
   file into a shared one used by all four DE roles:
   - Rename `home/gnome-common-desktop.nix` → `home/gnome-common-browser.nix`,
     update its header comment to reflect it now applies to every role that
     installs `brave-origin` (desktop, server, htpc, stateless), not just
     desktop.
   - Update `home-desktop.nix`'s import from
     `./home/gnome-common-desktop.nix` to `./home/gnome-common-browser.nix`.
   - Add `./home/gnome-common-browser.nix` to the imports of `home-server.nix`,
     `home-htpc.nix`, `home-stateless.nix`.
3. **Stale dock migration** — add the same one-shot
   `vexos-migrate-dock-brave-origin` systemd user service (verbatim logic:
   reads `/org/gnome/shell/favorite-apps`, sed-replaces
   `brave-browser.desktop` → `brave-origin.desktop`, stamp-guarded) to
   `home-server.nix`, `home-htpc.nix`, `home-stateless.nix`, matching the
   existing block in `home-desktop.nix`.

## Implementation Steps (Module Architecture Pattern — Option B)

- `modules/gnome-server.nix`, `modules/gnome-htpc.nix`,
  `modules/gnome-stateless.nix` remain role-specific addition files (no new
  `lib.mkIf` guards) — only the literal string value in `favorite-apps` changes.
- `home/gnome-common-browser.nix` is a shared addition file consumed by all
  four DE roles' home configs — analogous to `home/gnome-common.nix`, but
  scoped to roles that install `brave-origin` (excludes vanilla/headless-server
  by simply not being imported there, per existing pattern).
- `home-server.nix`, `home-htpc.nix`, `home-stateless.nix`: add one import
  line each, plus the migration systemd unit (copy-paste from
  `home-desktop.nix`, service name unchanged — it is a per-user unit, no
  cross-role collision).

## Dependencies

None — no new external library or flake input. Context7 verification not
required (internal-only Home Manager / dconf changes).

## Configuration Changes

- `modules/gnome-server.nix`, `modules/gnome-htpc.nix`,
  `modules/gnome-stateless.nix`: `favorite-apps` first entry.
- `home/gnome-common-desktop.nix` → renamed `home/gnome-common-browser.nix`.
- `home-desktop.nix`, `home-server.nix`, `home-htpc.nix`,
  `home-stateless.nix`: imports + migration systemd service.

## Risks and Mitigations

- **Risk:** stale user dconf `favorite-apps` on already-deployed server/htpc/
  stateless machines would keep showing a broken `brave-browser.desktop`
  icon after the system default changes. **Mitigation:** migration service
  added to each role, mirroring the desktop role's existing fix.
- **Risk:** `vanilla`/`headless-server` accidentally picking up brave-origin
  wiring. **Mitigation:** the new shared file is only imported by the four
  home files explicitly listed above; vanilla/headless-server home files are
  untouched.
- **Risk:** `brave-origin.desktop` not resolvable at runtime.
  **Mitigation:** already verified — `vexos.brave-origin` is installed via
  `modules/packages-desktop.nix`, imported by all four target roles'
  `configuration-*.nix`.
