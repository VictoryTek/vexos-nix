# PhotoGIMP Desktop Override — Research Spec

**Feature:** Fix GIMP `.desktop` name/icon not changing to PhotoGIMP after `nixos-rebuild switch`  
**Date:** 2026-03-26  
**Scope:** `home/photogimp.nix`

---

## 1. Current State Analysis

### What the code does

`home/photogimp.nix` attempts to rebrand GIMP as PhotoGIMP using four mechanisms:

| Step | Code | Result path |
|---|---|---|
| Icons | `xdg.dataFile."icons/hicolor"` with `recursive = true` | `~/.local/share/icons/hicolor/<size>/apps/photogimp.png` |
| `.desktop` override | `xdg.desktopEntries."org.gimp.GIMP"` | `/etc/profiles/per-user/nimda/share/applications/org.gimp.GIMP.desktop` |
| GIMP config copy | `home.activation.installPhotoGIMP` | `~/.config/GIMP/3.0/` |
| Cache refresh | `home.activation.refreshPhotoGIMPDesktopIntegration` | On-disk `icon-theme.cache` + `mimeinfo.cache` |

### How `xdg.desktopEntries` places files

Home Manager's `xdg.desktopEntries` module ([source: `modules/misc/xdg-desktop-entries.nix`](https://github.com/nix-community/home-manager/blob/main/modules/misc/xdg-desktop-entries.nix)) does **not** write files to `~/.local/share/applications/`. Instead it uses:

```nix
home.packages = (
  map lib.hiPrio            # higher priority than other packages
    (lib.attrsets.mapAttrsToList makeFile config.xdg.desktopEntries)
);
```

Because `home-manager.useUserPackages = true` is set in `flake.nix`, user packages go to `/etc/profiles/per-user/nimda/`. The `.desktop` file therefore lands at:

```
/etc/profiles/per-user/nimda/share/applications/org.gimp.GIMP.desktop
```

This path is in `XDG_DATA_DIRS` (the Home Manager NixOS module adds the user profile share path to `XDG_DATA_DIRS`). It is **not** in `XDG_DATA_HOME/applications/` (`~/.local/share/applications/`).

### Where GIMP's Flatpak `.desktop` lives

GIMP is installed as a **system Flatpak** via the `flatpak-install-apps` systemd service in `modules/flatpak.nix`. Its `.desktop` file is at:

```
/var/lib/flatpak/exports/share/applications/org.gimp.GIMP.desktop
```

`flatpak.nix` adds this path to `XDG_DATA_DIRS` via `lib.mkAfter`:

```nix
environment.sessionVariables = {
  XDG_DATA_DIRS = lib.mkAfter [
    "/var/lib/flatpak/exports/share"
    "$HOME/.local/share/flatpak/exports/share"
  ];
};
```

`lib.mkAfter` places these paths at the **end** of `XDG_DATA_DIRS`, so the Nix profile path comes earlier.

### `xdg.enable` status

`home.nix` does **not** set `xdg.enable = true`. This is acceptable — `xdg.dataFile`, `xdg.configFile`, and `xdg.desktopEntries` all work without it. `XDG_DATA_HOME` falls back to the spec default of `~/.local/share`.

### Icon installation

The code:
```nix
xdg.dataFile."icons/hicolor" = {
  source    = photogimp + "/.local/share/icons/hicolor";
  recursive = true;
};
```

The PhotoGIMP 3.0 repository at tag `3.0` **does** contain the hicolor icon structure at the expected path:

```
.local/share/icons/hicolor/
  16x16/apps/photogimp.png
  32x32/apps/photogimp.png
  48x48/apps/photogimp.png
  64x64/apps/photogimp.png
  128x128/apps/photogimp.png
  256x256/apps/photogimp.png
  512x512/apps/photogimp.png
  photogimp.png          ← stray file at hicolor root (harmless)
```

Source: [GitHub tree browse confirmed](https://github.com/Diolinux/PhotoGIMP/tree/3.0/.local/share/icons/hicolor).  
The `recursive = true` creates per-file symlinks, so all size-specific files are correctly installed into `~/.local/share/icons/hicolor/<size>/apps/photogimp.png`. The stray root-level `photogimp.png` symlink is also created but harmless — icon theme lookup never looks at the hicolor root.

---

## 2. Root Cause Analysis

### Root Cause 1 (PRIMARY): GFileMonitor does not reliably detect Nix profile atomic updates

**XDG lookup order:**
1. `$XDG_DATA_HOME/applications/` = `~/.local/share/applications/` — **checked first, always wins**
2. `$XDG_DATA_DIRS` paths in declared order (profile path, then Flatpak paths last)

`xdg.desktopEntries` puts the override in `XDG_DATA_DIRS` path #2 (the Nix profile), not path #1. This still takes priority over the Flatpak entry because `lib.mkAfter` puts Flatpak last.

**However**, when `nixos-rebuild switch` runs, the Nix profile is updated atomically: the symlink target of `/nix/var/nix/profiles/per-user/nimda/home-manager` is replaced with a new store path. From GNOME Shell's perspective:

- GNOME Shell's `ShellAppSystem` monitors `XDG_DATA_DIRS` paths via `GFileMonitor` (backed by inotify).
- The watched path `/etc/profiles/per-user/nimda/share/applications/` is a **symlink chain** into the Nix store.
- When the profile target changes atomically (ancestor symlink replaced), the **directory inode** that `GFileMonitor` has been watching ceases to exist at the watched path — new content is now at a different inode.
- inotify does not fire an `IN_MODIFY` or `IN_CREATE` for files inside the new (different-inode) directory.
- GNOME Shell does **not** reload its app list.

**Result:** Immediately after `nixos-rebuild switch`, GNOME Shell continues to display GIMP name and icon from its stale in-memory cache. Even though the correct PhotoGIMP `.desktop` is on disk in the Nix profile, GNOME Shell hasn't read it yet.

A **GNOME session restart** (logout → login) triggers a fresh `g_app_info_get_all()` scan, which sees the Nix profile path before the Flatpak path in `XDG_DATA_DIRS` and loads the PhotoGIMP override correctly. However, requiring a full logout after every `nixos-rebuild switch` is poor UX.

### Root Cause 2 (SECONDARY): Missing `X-Flatpak` key breaks window-to-app matching

The Flatpak `.desktop` at `/var/lib/flatpak/exports/share/applications/org.gimp.GIMP.desktop` contains:
```ini
X-Flatpak=org.gimp.GIMP
```

The HM-generated override has **no** `X-Flatpak` key. GNOME Shell 46+ uses `X-Flatpak` to associate a running window (identified by its Wayland/X11 app ID `org.gimp.GIMP`) to a `.desktop` entry. When GIMP runs:

1. GNOME Shell looks up `org.gimp.GIMP` as an app ID.
2. It searches for a `.desktop` whose `X-Flatpak` field matches `org.gimp.GIMP`.
3. The HM override does **not** match this criterion.
4. GNOME Shell falls back to the Flatpak-exported `.desktop` for the **running app indicator** (taskbar, window switcher, dash-to-dock).

**Effect:** Even after a session restart, the app **grid** might show "PhotoGIMP" (because `XDG_DATA_DIRS` priority is correct for the grid scan), but the **running GIMP window** in the dock/switcher shows "GIMP" with the original icon because window-to-app matching uses the `X-Flatpak` field from the Flatpak entry.

This explains the symptom holistically: both name and icon remain GIMP defaults in interactive use.

### Root Cause 3 (TERTIARY): In-session icon theme cache not refreshed immediately

`home.activation.refreshPhotoGIMPDesktopIntegration` correctly runs:
```bash
gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor"
```

This updates `~/.local/share/icons/hicolor/icon-theme.cache` on disk. GLib's `GFileMonitor` watches this cache file and can reload the icon theme when it changes. However:

- If GNOME Shell has not yet detected the `icon-theme.cache` change (debounce timer, 2–3 seconds typical), the `photogimp` icon may not display immediately.
- This is a minor timing issue, not a persistent failure.

### Summary table

| Root Cause | Severity | Symptom | Persists after logout/login? |
|---|---|---|---|
| RC1: `GFileMonitor` misses Nix atomic profile swap | **Critical** | Name/icon stays GIMP after `nixos-rebuild switch` | No (session restart fixes it) |
| RC2: Missing `X-Flatpak` key | **High** | Running window shows GIMP branding in dock/switcher | Yes — always wrong for running apps |
| RC3: Icon cache refresh timing | Low | Brief flicker or old icon immediately post-switch | No (resolves within seconds) |

---

## 3. Proposed Solution

The fix has two parts. Both are required to fully resolve the issue.

### Part A — Fix the `.desktop` override placement (resolves RC1)

**Replace** `xdg.desktopEntries."org.gimp.GIMP"` with `xdg.dataFile."applications/org.gimp.GIMP.desktop"`.

`xdg.dataFile` places the file as a **symlink directly in `~/.local/share/applications/`**  
(`XDG_DATA_HOME/applications/` — the highest-priority lookup path for GLib/GNOME). This:

1. Definitively overrides the Flatpak `.desktop` regardless of `XDG_DATA_DIRS` ordering.
2. Creates a **file-level** symlink in a stable real directory; inotify fires correctly on creation/update, so GNOME Shell reloads its app list in the running session without requiring logout.
3. Removes the need to worry about Nix profile path ordering in `XDG_DATA_DIRS`.

The `cleanupPhotogimpOrphanFiles` activation step (which runs `entryBefore [ "checkLinkTargets" ]`) remains needed to remove any legacy non-symlink file at `~/.local/share/applications/org.gimp.GIMP.desktop` so Home Manager can create the managed symlink.

### Part B — Add `X-Flatpak` key (resolves RC2)

Include `X-Flatpak=org.gimp.GIMP` in the override `.desktop` content so that GNOME Shell's Flatpak-aware window-to-app matching correctly selects the PhotoGIMP override when a GIMP window is running.

---

## 4. Specific Code Changes Required in `home/photogimp.nix`

### Remove `xdg.desktopEntries."org.gimp.GIMP"` (lines ~120–166 in current file)

Delete the entire `xdg.desktopEntries."org.gimp.GIMP" = { ... };` block.

### Add `xdg.dataFile."applications/org.gimp.GIMP.desktop"` in its place

```nix
# ── Step 5: override GIMP .desktop with PhotoGIMP branding ────────────
# Written to ~/.local/share/applications/org.gimp.GIMP.desktop — this path is
# XDG_DATA_HOME/applications/, which GLib checks BEFORE any XDG_DATA_DIRS entry
# (including /var/lib/flatpak/exports/share). A file-level symlink here also
# triggers GFileMonitor correctly inside a running GNOME session, so the name
# and icon update without requiring a logout.
#
# X-Flatpak=org.gimp.GIMP is required so GNOME Shell's Flatpak-aware window
# matching picks this override (not the original Flatpak entry) when a GIMP
# window is running in the dock / switcher / app-switcher.
xdg.dataFile."applications/org.gimp.GIMP.desktop".text = ''
  [Desktop Entry]
  Type=Application
  Version=1.1
  Name=PhotoGIMP
  GenericName=Image Editor
  Comment=Create images and edit photographs
  Exec=flatpak run org.gimp.GIMP %U
  Icon=photogimp
  Terminal=false
  StartupNotify=true
  Categories=Graphics;2DGraphics;RasterGraphics;GTK;
  MimeType=image/bmp;image/g3fax;image/gif;image/jpeg;image/png;image/tiff;image/webp;image/heif;image/heic;image/svg+xml;image/x-bmp;image/x-compressed-xcf;image/x-exr;image/x-gimp-gbr;image/x-gimp-gih;image/x-gimp-pat;image/x-icon;image/x-pcx;image/x-portable-anymap;image/x-portable-bitmap;image/x-portable-graymap;image/x-portable-pixmap;image/x-psd;image/x-sgi;image/x-tga;image/x-wmf;image/x-xcf;image/x-xcursor;image/x-xpixmap;image/x-xwindowdump;image/jp2;application/pdf;application/postscript;
  X-Flatpak=org.gimp.GIMP
  Keywords=GIMP;PhotoGIMP;graphic;design;illustration;painting;
'';
```

### No other changes needed

- The icon installation at `xdg.dataFile."icons/hicolor"` is correct; keep as-is.
- All three activation steps (`cleanupPhotogimpOrphanFiles`, `installPhotoGIMP`, `refreshPhotoGIMPDesktopIntegration`) remain correct and needed.
- `flatpak.nix` requires no changes.
- `home.nix` requires no changes.

---

## 5. Verification

After applying the fix and running `nixos-rebuild switch`, the following should hold **without any session restart**:

1. `~/.local/share/applications/org.gimp.GIMP.desktop` is a symlink into the Nix store and contains `Name=PhotoGIMP`, `Icon=photogimp`, `X-Flatpak=org.gimp.GIMP`.
2. GNOME Activities grid shows "PhotoGIMP" name with the PhotoGIMP icon (within a few seconds of activation completing, once GFileMonitor fires).
3. Launching GIMP and hovering the dock entry shows "PhotoGIMP".
4. The `photogimp` icon resolves from `~/.local/share/icons/hicolor/<size>/apps/photogimp.png` (confirmed by `gtk-update-icon-cache` output and the icon appearing in GNOME's launcher).

To manually verify the lookup is working:
```bash
# Check the file exists as a symlink
ls -la ~/.local/share/applications/org.gimp.GIMP.desktop

# Check icon installation
ls ~/.local/share/icons/hicolor/256x256/apps/photogimp.png

# Check the desktop database
grep -r "PhotoGIMP" ~/.local/share/applications/
```

---

## 6. Risks and Caveats

| Risk | Likelihood | Mitigation |
|---|---|---|
| `xdg.dataFile` text content drifts from upstream GIMP MIME list | Low | The MIME list is stable between GIMP 3.x updates; check when GIMP major version bumps |
| GNOME Shell still shows old icon for ~2–3 seconds after activation (RC3) | Low | Expected; `GFileMonitor` debounce. Not a bug — resolves automatically |
| `home.stateVersion = "24.05"` and `home-manager/release-25.11` mismatch means some HM defaults may differ | Cosmetic | Does not affect this feature |
| If the user has manually placed a real file at `~/.local/share/applications/org.gimp.GIMP.desktop`, `cleanupPhotogimpOrphanFiles` removes it before HM creates the symlink | Intended | The cleanup activation step is already in place for exactly this scenario |
| PhotoGIMP rev `3.0` hash `sha256-R9MMidsR2+QFX6tu+j5k2BejxZ+RGwzA0DR9GheO89M=` must remain valid | Low | If the tag is re-pushed upstream the hash breaks the build — monitor upstream releases |

---

## 7. References

- Home Manager `xdg.desktopEntries` source: `modules/misc/xdg-desktop-entries.nix` — confirms `home.packages` placement via `lib.hiPrio`
- Home Manager `xdg.desktopEntries.settings` option: accepts `attrsOf str` for arbitrary extra `[Desktop Entry]` keys
- PhotoGIMP 3.0 repo `.local/share/icons/hicolor/` tree: sizes 16×16 through 512×512 confirmed present
- PhotoGIMP 3.0 repo `.local/share/applications/org.gimp.GIMP.desktop`: uses `Icon=photogimp`, no `X-Flatpak` key, `Exec` hardcoded to `gimp-2.10` (incompatible with GIMP 3.0)
- XDG Base Directory Spec: `XDG_DATA_HOME/applications/` is searched before any `XDG_DATA_DIRS` entry
- GNOME Shell 46+ Flatpak window matching: uses `X-Flatpak` field for window-to-app association
- `lib.mkAfter`: places Flatpak paths at end of `XDG_DATA_DIRS` — correct, does not cause the bug
