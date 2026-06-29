# Brave Origin Dock Migration & mailto Fix — Spec

## Current State Analysis

### Issue 1: Dock favorite not updated
- `modules/gnome-desktop.nix` declares `favorite-apps` with `brave-origin.desktop`
  via `programs.dconf.profiles.user.databases[*].settings`.
- This creates a **system-level dconf database** that provides defaults.
- The user's dconf database at `~/.config/dconf/user` has higher priority and
  contains a stale entry: `brave-browser.desktop` as the first dock item.
- This user-level entry originates from when `dconf.settings` (home-manager) was
  used to write dock favorites directly into the user dconf — before the system
  database approach was adopted.
- Result: system default (`brave-origin.desktop`) is invisible because the user
  dconf override (`brave-browser.desktop`) always wins.

### Issue 2: Zen browser is mailto default
- `home/gnome-common-desktop.nix` declares MIME defaults for:
  `http`, `https`, `text/html`, `application/xhtml+xml`, `ftp`
- `x-scheme-handler/mailto` was never declared anywhere in vexos-nix.
- Zen browser's `.desktop` file declares `x-scheme-handler/mailto` in its MimeType
  list. With no explicit default set, the freedesktop resolver picks zen as the
  registered handler.
- Result: clicking mailto: links opens zen instead of brave-origin.

## Proposed Solution

### Fix 1: Migration stamp service (dock)

Add a systemd user service to `home-desktop.nix` with a stamp file. It:
1. Checks if `brave-browser.desktop` appears in the user's current dconf
   `favorite-apps` value.
2. If so, replaces it in-place with `brave-origin.desktop` via `dconf write`.
3. Exits immediately if stamp exists (idempotent; user dock customizations after
   migration are preserved).

This follows the exact pattern of `vexos-init-app-folders` and
`vexos-init-extensions` already present in `home-desktop.nix`.

Stamp path: `$HOME/.local/share/vexos/.dock-brave-origin-migration-v1`

Naming: service key `vexos-migrate-dock-brave-origin`, consistent with
`vexos-init-*` pattern.

### Fix 2: Add mailto MIME default (home/gnome-common-desktop.nix)

Add one line to the `xdg.mimeApps.defaultApplications` attrset:
```
"x-scheme-handler/mailto" = [ "brave-origin.desktop" ];
```

This is a surgical addition to the existing MIME block in `home/gnome-common-desktop.nix`.

## Implementation Steps

1. `home-desktop.nix`: add `vexos-migrate-dock-brave-origin` systemd user service
   with stamp-file guard.
2. `home/gnome-common-desktop.nix`: add `x-scheme-handler/mailto` to
   `defaultApplications`.

## Files Modified

- `home-desktop.nix`
- `home/gnome-common-desktop.nix`

## Dependencies

None — no new flake inputs, no new packages.

## Risks & Mitigations

- **Risk:** stamp service runs before GNOME shell is ready and `dconf write` fails.
  **Mitigation:** service is `After = graphical-session.target`, same as existing
  init services which are proven to work.
- **Risk:** user has already manually changed dock; migration wipes brave-browser
  but leaves brave-origin in place of it — other user entries are untouched.
  **Mitigation:** `sed` replacement is surgical; only the string
  `brave-browser.desktop` is changed. All other dock entries are preserved.
- **Risk:** `brave-origin.desktop` does not actually handle mailto (browser may
  not open webmail composer). **Mitigation:** this matches the original behavior —
  brave-browser also declared mailto in its MimeType and was the previous implicit
  default before zen installed itself.
