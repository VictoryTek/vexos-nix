# Spec: Stateless Role Bug Fixes

**Feature name:** `stateless_fixes`  
**Date:** 2026-04-20  
**Status:** Ready for Implementation  

---

## Summary of Issues

| # | Issue | Root Cause | Fix |
|---|-------|-----------|-----|
| 1 | PhotoGIMP branding in stateless app grid | Photogimp cleanup activations are gated behind `photogimp.enable` — never fire on stateless since the module is not imported; orphaned desktop entry and icons survive | Add explicit cleanup activation to `home-stateless.nix` |
| 2 | Tor Browser not visible in dock | `tor-browser` package IS correctly installed; `torbrowser.desktop` is missing from `favorite-apps` | Add `torbrowser.desktop` to `favorite-apps` list |

---

## Issue 1: PhotoGIMP Appears in Stateless App Grid

### Current State

**`home/photogimp.nix`** (the PhotoGIMP Home Manager module):
- Declares `options.photogimp.enable` with all config inside `lib.mkIf config.photogimp.enable { ... }`
- When enabled, creates `~/.local/share/applications/org.gimp.GIMP.desktop` as a **symlink** via `xdg.dataFile."applications/org.gimp.GIMP.desktop"` with `Name=PhotoGIMP`
- When enabled, creates PhotoGIMP icon symlinks under `~/.local/share/icons/hicolor/` via `xdg.dataFile."icons/hicolor"` (recursive)
- Contains `home.activation.cleanupPhotogimpOrphanFiles` that only removes **real files** (`[ -f FILE ] && [ ! -L FILE ]`) — does NOT remove symlinks
- This entire cleanup is inside `lib.mkIf config.photogimp.enable` — it ONLY runs when PhotoGIMP is enabled

**`home-desktop.nix`**:
- Imports `./home/photogimp.nix`
- Sets `photogimp.enable = true`

**`home-stateless.nix`**:
- Does NOT import `./home/photogimp.nix`
- Does NOT define any `xdg.dataFile` for GIMP or PhotoGIMP
- Contains NO activation script to clean up any PhotoGIMP-related files

**`modules/packages.nix`**: GIMP is NOT installed system-wide (packages: brave, just, btop, inxi, git, curl, wget only).

**`modules/flatpak.nix`** defaultApps: GIMP is NOT in the default Flatpak app list.

**`modules/impermanence.nix`**: User home directories are fully ephemeral (no home persistence declared). However, the stateless system persists `/etc/nixos/` (for the config) and `/var/lib/nixos/`. The home itself is wiped on every reboot.

**`flake.nix`**:
- `statelessModules` uses `statelessHomeManagerModule` → `./home-stateless.nix` (correct, NOT the desktop config)
- The desktop and stateless Home Manager configs are properly separated

### Root Cause

All activation scripts and `xdg.dataFile` entries in `home/photogimp.nix` are inside `lib.mkIf config.photogimp.enable`. Since `home-stateless.nix` **never imports `photogimp.nix`**, there is **no module-level option, no activation, and no cleanup** provided for the stateless role.

Two scenarios produce the orphan:

1. **In-session migration**: The user ran `nixos-rebuild switch --flake .#vexos-stateless-amd` on a machine that previously had the desktop Home Manager config active. Before rebooting (so the home directory was not yet wiped by the tmpfs), the old desktop Home Manager generation had left `~/.local/share/applications/org.gimp.GIMP.desktop` as a symlink. When the new stateless Home Manager activation ran, it should have removed that symlink — BUT only if the PREVIOUS generation had that file tracked. If the file was introduced via a HM generation that was already garbage-collected, or if HM was skipped during the role switch, the symlink/file persists.

2. **Real file orphan**: If the user ever manually installed PhotoGIMP configs (before the Nix module existed), a real file at `~/.local/share/applications/org.gimp.GIMP.desktop` exists. The cleanup in `photogimp.nix` removes real files ONLY when PhotoGIMP is enabled. Since it is never enabled on stateless, this real file is never cleaned.

**Critical code observation in `photogimp.nix`:**
```bash
# Existing cleanup — only removes REAL FILES, NOT symlinks:
if [ -f "$DESKTOP_FILE" ] && [ ! -L "$DESKTOP_FILE" ]; then
  $DRY_RUN_CMD rm -f "$DESKTOP_FILE"
fi
```
Even if `photogimp.nix` were imported with `enable = false` (Option A), the cleanup still would not fire because it is inside `lib.mkIf config.photogimp.enable`. Option A is therefore NOT a valid fix.

### Proposed Fix

**Option B: Add a standalone cleanup activation to `home-stateless.nix`**

Add the following block to `home-stateless.nix`, after the `home.file."justfile"` line and before the hidden app grid entries section:

```nix
# ── PhotoGIMP orphan cleanup ───────────────────────────────────────────────
# Removes any leftover PhotoGIMP desktop entry or icon overrides from a
# previous desktop-role Home Manager generation or manual PhotoGIMP install.
# The photogimp.nix module is never imported on stateless; all its cleanup
# activations are gated behind photogimp.enable = true and never fire here.
# This activation removes BOTH real files AND symlinks (unlike the cleanup in
# photogimp.nix which only removes real files).
home.activation.cleanupPhotogimpOrphans =
  lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    DESKTOP_FILE="$HOME/.local/share/applications/org.gimp.GIMP.desktop"
    if [ -e "$DESKTOP_FILE" ] || [ -L "$DESKTOP_FILE" ]; then
      $VERBOSE_ECHO "Stateless: removing orphaned PhotoGIMP desktop entry"
      $DRY_RUN_CMD rm -f "$DESKTOP_FILE"
    fi

    for size in 16x16 32x32 48x48 64x64 128x128 256x256 512x512; do
      ICON_FILE="$HOME/.local/share/icons/hicolor/$size/apps/photogimp.png"
      if [ -e "$ICON_FILE" ] || [ -L "$ICON_FILE" ]; then
        $VERBOSE_ECHO "Stateless: removing orphaned PhotoGIMP icon $size"
        $DRY_RUN_CMD rm -f "$ICON_FILE"
      fi
    done

    for stray in \
      "$HOME/.local/share/icons/hicolor/photogimp.png" \
      "$HOME/.local/share/icons/hicolor/256x256/256x256.png"; do
      if [ -e "$stray" ] || [ -L "$stray" ]; then
        $VERBOSE_ECHO "Stateless: removing stray PhotoGIMP file $stray"
        $DRY_RUN_CMD rm -f "$stray"
      fi
    done

    APP_DIR="$HOME/.local/share/applications"
    ICON_DIR="$HOME/.local/share/icons/hicolor"
    if [ -d "$APP_DIR" ]; then
      $VERBOSE_ECHO "Stateless: refreshing desktop database after PhotoGIMP cleanup"
      $DRY_RUN_CMD ${pkgs.desktop-file-utils}/bin/update-desktop-database "$APP_DIR"
    fi
    if [ -d "$ICON_DIR" ]; then
      $VERBOSE_ECHO "Stateless: refreshing icon cache after PhotoGIMP cleanup"
      $DRY_RUN_CMD ${pkgs.gtk3}/bin/gtk-update-icon-cache -f -t "$ICON_DIR"
    fi
  '';
```

**Why `entryBefore [ "checkLinkTargets" ]`**: Same ordering used by the photogimp.nix cleanup. Removes orphaned real files before Home Manager's link-check phase would fail on them.

**Why `-e OR -L`**: `-e` matches real files and valid symlinks (follows the link); `-L` matches any symlink including broken ones. Together they cover all cases: real file, valid symlink, broken symlink.

**File to modify:** `home-stateless.nix`

**Placement:** After `home.file."justfile".source = ./justfile;` and before the `# ── Hidden app grid entries` comment block.

---

## Issue 2: Tor Browser Not Visible / Not in Dock

### Current State

**`home-stateless.nix` packages list (lines 15–17):**
```nix
home.packages = with pkgs; [
  # Privacy browser
  tor-browser  # Routes traffic through the Tor network (Tails-like stateless role)
```

**Attribute name verification:**
- `nix eval --raw nixpkgs#tor-browser.pname` → `"tor-browser"` ✔ (valid attribute)
- Package resolves to `tor-browser-15.0.9` in the project's pinned nixpkgs (`github:NixOS/nixpkgs/nixos-25.11`)
- Desktop entry file provided by the package: `/share/applications/torbrowser.desktop`
- Desktop entry `Name=Tor Browser`

**`home-stateless.nix` favorite-apps list:**
```nix
favorite-apps = [
  "brave-browser.desktop"
  "app.zen_browser.zen.desktop"
  "org.gnome.Nautilus.desktop"
  "com.mitchellh.ghostty.desktop"
  "io.github.up.desktop"
];
```
`torbrowser.desktop` is **NOT** in the favorite-apps list.

### Root Cause

The `tor-browser` package attribute IS correct and the package IS already declared in `home.packages`. There is **no installation bug**.

The likely user complaint is one of:
1. **`home-manager switch` was not re-run** after the package was added to the config — Tor Browser would not appear until Home Manager activates the new generation
2. **Tor Browser is not pinned to the dock** — it appears in the app grid alphabetically but not in the dash/favorites, making it less discoverable on a privacy-focused role where it is the primary browser for sensitive sessions

The stateless role is described as "Tails-like stateless" with Tor Browser as the privacy-oriented browser. For this role, it is appropriate that `torbrowser.desktop` be visible in the dock alongside the other browsers.

### Proposed Fix

**Add `torbrowser.desktop` to the `favorite-apps` list** in `home-stateless.nix`.

Current:
```nix
favorite-apps = [
  "brave-browser.desktop"
  "app.zen_browser.zen.desktop"
  "org.gnome.Nautilus.desktop"
  "com.mitchellh.ghostty.desktop"
  "io.github.up.desktop"
];
```

Updated (insert `torbrowser.desktop` after zen, before Nautilus — browser grouping):
```nix
favorite-apps = [
  "brave-browser.desktop"
  "app.zen_browser.zen.desktop"
  "torbrowser.desktop"
  "org.gnome.Nautilus.desktop"
  "com.mitchellh.ghostty.desktop"
  "io.github.up.desktop"
];
```

**File to modify:** `home-stateless.nix`  
**Placement:** `dconf.settings."org/gnome/shell".favorite-apps` list, third position (after zen, before Nautilus)

---

## Files to Modify

| File | Change |
|------|--------|
| `home-stateless.nix` | Add `home.activation.cleanupPhotogimpOrphans` block (Issue 1) |
| `home-stateless.nix` | Add `"torbrowser.desktop"` to `favorite-apps` (Issue 2) |

No new files need to be created. No new dependencies are introduced. No changes to any system module, flake input, or `flake.nix`.

---

## Implementation Steps

1. Open `home-stateless.nix`
2. After `home.file."justfile".source = ./justfile;` and before `# ── Hidden app grid entries`, add the `home.activation.cleanupPhotogimpOrphans` block exactly as specified above
3. In `dconf.settings."org/gnome/shell".favorite-apps`, insert `"torbrowser.desktop"` as the third entry (after `"app.zen_browser.zen.desktop"`, before `"org.gnome.Nautilus.desktop"`)
4. Run `nix flake check` to validate the flake evaluates without errors
5. Run `sudo nixos-rebuild dry-build --flake .#vexos-stateless-amd` to verify the stateless AMD closure builds

---

## Risk Assessment

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| Cleanup activation removes a legitimate file | Very Low | The file `~/.local/share/applications/org.gimp.GIMP.desktop` should NEVER exist on stateless (GIMP not installed, module not imported); if it does exist it is definitionally an orphan |
| `pkgs.desktop-file-utils` or `pkgs.gtk3` unavailable | None | Both are standard nixpkgs packages available as `pkgs.*` in any HM context |
| `torbrowser.desktop` ID incorrect | None | Verified from the built package: `/share/applications/torbrowser.desktop` with `Name=Tor Browser` |
| Cleanup causes icon/database refresh on every fresh stateless boot | Negligible | The conditional `if [ -e ... ]` guards prevent the refresh unless files actually exist; on a fresh tmpfs home the orphan files would not exist |

---

## Verification After Implementation

- `nix flake check` must pass
- `sudo nixos-rebuild dry-build --flake .#vexos-stateless-amd` must succeed
- After `home-manager switch` on the stateless role: PhotoGIMP entry (`~/.local/share/applications/org.gimp.GIMP.desktop`) must not exist
- Tor Browser (`torbrowser.desktop`) must appear as the 3rd item in the GNOME dock
