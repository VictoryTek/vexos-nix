# Review: Server Branding + Global dconf Settings

**Feature:** `server_branding_dconf_globals`
**Review Date:** 2026-04-17
**Reviewer:** Review Subagent (Phase 3)
**Status:** NEEDS_REFINEMENT

---

## 1. Summary

The implementation correctly creates `home/gnome-common.nix` and updates all four role home
files to import it. The shared module is architecturally clean, contains no disallowed keys
(no `picture-uri`, `picture-uri-dark`, no `enabled-extensions`), and all per-role files
retain their role-specific content. The critical BUG-1 (HTPC missing `enabled-extensions`)
is resolved.

**However, the build fails with a hard error** because `home/gnome-common.nix` was created
on disk but never staged in git. Nix flake evaluation copies only git-tracked file trees to
the store. The untracked file is absent from the store path, causing evaluation to abort.

---

## 2. Build Validation

### `nix flake check --impure`

```
warning: Git tree '/home/nimda/Projects/vexos-nix' is dirty
error: path '/nix/store/gdqxl6injrcsjv9nlhrm7906l6pn7x4a-source/home/gnome-common.nix'
       does not exist
```

**Result: FAIL**

### `sudo nixos-rebuild dry-build` commands

Not executable in this environment (container `no_new_privs` flag). However the flake check
error above confirms all three dry-builds would fail with the same root cause.

### Cause

```
git status output:
 M home-desktop.nix        (modified, unstaged)
 M home-htpc.nix           (modified, unstaged)
 M home-server.nix         (modified, unstaged)
 M home-stateless.nix      (modified, unstaged)
?? home/gnome-common.nix   (untracked — NOT in git index)
```

Nix evaluates flakes from a git-derived store path. New files must be staged with
`git add` before Nix can see them. The four modified files are in the working tree but
not staged; this does not block evaluation of those files (Nix uses the on-disk working
copy when the tree is dirty). However, a completely **untracked** file is excluded from
the git working-tree copy Nix constructs, causing the hard "does not exist" error.

---

## 3. Issues Found

### CRITICAL

| # | Issue | File | Detail |
|---|-------|------|--------|
| C-1 | `home/gnome-common.nix` is untracked in git | `home/gnome-common.nix` | File exists on disk but `git ls-files home/gnome-common.nix` returns nothing. Nix cannot find it in the store path during flake evaluation. **Fix:** `git add home/gnome-common.nix` |

### WARNING

| # | Issue | File | Detail |
|---|-------|------|--------|
| W-1 | Modified home files not staged | `home-{desktop,server,htpc,stateless}.nix` | All four show as ` M` (unstaged). While this does not break the current dirty-tree evaluation by itself, staging all changes together with the new file is required for a consistent commit and clean preflight run. |

### INFO

| # | Issue | File | Detail |
|---|-------|------|--------|
| I-1 | Desktop `enabled-extensions` count: 12 vs spec's "13" | `home-desktop.nix` | The spec inventory table claims 13 extensions for desktop. Post-implementation the list contains 12 entries. Since the refactor did not touch the extensions list at all (it is role-specific and was never in the common module), this discrepancy pre-dates this change. The spec count was likely slightly off at authoring time. No regression. |

---

## 4. Positive Findings

### `home/gnome-common.nix`

- ✅ Contains ONLY truly shared keys — no role-specific content
- ✅ No `picture-uri` or `picture-uri-dark` present
- ✅ No `enabled-extensions` present
- ✅ No `favorite-apps` present
- ✅ Packages `bibata-cursors` and `kora-icon-theme` correctly moved here
- ✅ `home.pointerCursor` declaration correct (name, package, size)
- ✅ GTK declarations (`gtk.enable`, `gtk.iconTheme`, `gtk.cursorTheme`) correct
- ✅ All 7 required dconf schema paths present with correct keys
- ✅ `lib.gvariant.mkUint32` used correctly for `lock-delay` and `idle-delay`
- ✅ Nix attribute-set syntax valid (braces, semicolons, string quoting)
- ✅ `{ pkgs, lib, ... }:` function signature correct — `lib` required for `gvariant`
- ✅ Follows the `home/photogimp.nix` sub-module pattern exactly

### `home-desktop.nix`

- ✅ Imports `./home/gnome-common.nix` correctly
- ✅ All shared dconf blocks removed (interface, wm/preferences, dash-to-dock, background-logo, screensaver, session)
- ✅ `picture-options` removed from `org/gnome/desktop/background` (moved to common)
- ✅ `picture-uri` / `picture-uri-dark` retained, pointing to `wallpapers/desktop/`
- ✅ `enabled-extensions` retained with gamemode extension
- ✅ `favorite-apps` retained (role-specific)
- ✅ All five app-folder definitions retained
- ✅ `bibata-cursors` and `kora-icon-theme` removed from `home.packages`
- ✅ `home.pointerCursor`, `gtk.*` blocks removed
- ✅ No duplicate keys between this file and `gnome-common.nix`

### `home-server.nix`

- ✅ Imports `./home/gnome-common.nix` correctly
- ✅ All shared dconf blocks removed
- ✅ `picture-uri` / `picture-uri-dark` retained, pointing to `wallpapers/server/`
- ✅ Server-role `enabled-extensions` (no gamemode) retained
- ✅ Server-specific `favorite-apps` retained
- ✅ Server-specific app-folder definitions (Office, Utilities, System) retained
- ✅ Background-logo dconf keys absent here (correctly delegated to common module)
- ✅ No duplicate keys with `gnome-common.nix`

### `home-htpc.nix`

- ✅ **BUG-1 RESOLVED:** `enabled-extensions` now present under `org/gnome/shell` with 11 entries (no gamemode) — all extensions will activate on HTPC
- ✅ Imports `./home/gnome-common.nix` correctly
- ✅ `picture-uri` / `picture-uri-dark` pointing to `wallpapers/htpc/`
- ✅ HTPC-only `org/gnome/settings-daemon/plugins/power` sleep settings retained
- ✅ `favorite-apps` retained with HTPC-specific app list (Plex, FreeTube, etc.)
- ✅ App-folder definitions retained
- ✅ No duplicate keys with `gnome-common.nix`

### `home-stateless.nix`

- ✅ Imports `./home/photogimp.nix` and `./home/gnome-common.nix` correctly
- ✅ All shared dconf blocks removed
- ✅ `picture-uri` / `picture-uri-dark` pointing to `wallpapers/desktop/` (stateless mirrors desktop — correct per design)
- ✅ `enabled-extensions` retained (11 items, no gamemode)
- ✅ `favorite-apps` retained
- ✅ App-folder definitions retained
- ✅ No duplicate keys with `gnome-common.nix`

---

## 5. Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 95% | A |
| Best Practices | 93% | A |
| Functionality | 82% | B |
| Code Quality | 95% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 96% | A |
| Build Success | 0% | F |

**Overall Grade: C+ (82.6%)**

> Build Success receives 0% due to the hard evaluation failure caused by the untracked file.
> All other categories score exceptionally well — the implementation is architecturally sound
> and correct. The single blocker is a git hygiene issue, not a code deficiency.

---

## 6. Required Fixes (Phase 4)

### Fix C-1 — Stage `home/gnome-common.nix` and all modified files

```bash
cd /home/nimda/Projects/vexos-nix
git add home/gnome-common.nix
git add home-desktop.nix home-server.nix home-htpc.nix home-stateless.nix
```

After staging, re-run:
```bash
nix flake check --impure
sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd
sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia
sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm
```

No code changes are needed — only `git add` to include `home/gnome-common.nix` in the git
index so that Nix can find it in the store-path during evaluation.

---

## 7. Verdict

**NEEDS_REFINEMENT**

The implementation is correct and complete in content. One critical blocking issue prevents
the build from succeeding: `home/gnome-common.nix` is not tracked by git and is therefore
absent from the Nix store copy used during flake evaluation. Staging the file resolves the
build failure, after which all validation checks are expected to pass without any code changes.
