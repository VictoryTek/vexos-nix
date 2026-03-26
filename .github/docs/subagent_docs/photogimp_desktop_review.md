# PhotoGIMP Desktop Override — Review

**Feature:** Fix GIMP `.desktop` name/icon not changing to PhotoGIMP  
**Date:** 2026-03-26  
**Reviewer:** Review Subagent  
**Files Reviewed:**
- `home/photogimp.nix`
- `.github/docs/subagent_docs/photogimp_desktop_spec.md`

---

## Build Validation

**Status: SKIPPED**

`nix` is not available in this Windows environment. Static review performed instead.

All Nix syntax has been reviewed by static analysis against known Nix language rules and Home Manager API conventions.

---

## Review Findings

### 1. Spec Compliance

**Result: MINOR DEVIATIONS**

The two core changes mandated by the spec are correctly implemented:

| Spec Requirement | Status |
|---|---|
| Replace `xdg.desktopEntries."org.gimp.GIMP"` with `xdg.dataFile."applications/org.gimp.GIMP.desktop"` | ✅ Done |
| Add `X-Flatpak=org.gimp.GIMP` to `.desktop` content | ✅ Done |
| File placed at `XDG_DATA_HOME/applications/` for correct GLib/GNOME lookup order | ✅ Correct |
| File-level symlink for reliable inotify/GFileMonitor detection | ✅ Correct (xdg.dataFile produces file-level symlink) |

**Minor deviations from the spec's code example (Section 4):**

| Field | Spec Example | Implementation | Impact |
|---|---|---|---|
| `Version=1.1` | Present | **Absent** | None — `.desktop` Version is cosmetic, ignored by all modern tooling |
| `Keywords=GIMP;PhotoGIMP;graphic;design;illustration;painting;` | Present | **Absent** | Low — omission reduces GNOME Activities keyword search results but does not affect core function |

These two fields are present in the spec's code example but are **not** listed in the review criteria checklist (Section 3 of the prompt). Neither affects functionality.

---

### 2. Nix Syntax Correctness

**Result: PASS**

The attribute form used:
```nix
xdg.dataFile."applications/org.gimp.GIMP.desktop" = {
  text = ''
    ...
  '';
};
```

This is semantically equivalent to the spec's `xdg.dataFile."applications/org.gimp.GIMP.desktop".text = ''...''` form. Both are valid Nix; the attrset literal form is idiomatic for multi-field configurations and consistent with the file's icon installation block.

**Multiline string analysis:**
- Opens with `text = ''` followed by a newline — ✅ correct indented string syntax
- Content lines are indented 8 spaces; closing `''` is at 6 spaces
- Nix strips the minimum non-empty-line indentation (8 spaces) from all content lines, producing a `.desktop` file with zero leading whitespace per line — ✅ correct format for `.desktop` files
- Final line before `''` has no trailing blank line — ✅ correct (Nix strips the final newline before the closing delimiter)

---

### 3. Desktop File Content

**Result: PASS**

All required fields verified:

| Field | Required | Present | Value |
|---|---|---|---|
| `[Desktop Entry]` section header | ✅ | ✅ | `[Desktop Entry]` |
| `Type=Application` | ✅ | ✅ | `Type=Application` |
| `Name=PhotoGIMP` | ✅ | ✅ | `Name=PhotoGIMP` |
| `Icon=photogimp` | ✅ | ✅ | `Icon=photogimp` |
| `Exec=flatpak run org.gimp.GIMP %U` | ✅ | ✅ | `Exec=flatpak run org.gimp.GIMP %U` |
| `X-Flatpak=org.gimp.GIMP` | ✅ | ✅ | `X-Flatpak=org.gimp.GIMP` |
| `Categories=` semicolon-terminated | ✅ | ✅ | `...RasterGraphics;GTK;` — ends with `;` |
| `MimeType=` semicolon-terminated | ✅ | ✅ | `...application/postscript;` — ends with `;` |
| `GenericName=Image Editor` | — | ✅ | Present |
| `Comment=Create images and edit photographs` | — | ✅ | Present |
| `Terminal=false` | — | ✅ | Present |
| `StartupNotify=true` | — | ✅ | Present |

---

### 4. Regression Check — Other Module Parts

**Result: PASS — No regressions**

| Component | Expected | Status |
|---|---|---|
| `home.activation.cleanupPhotogimpOrphanFiles` (entryBefore checkLinkTargets) | Present | ✅ Intact — cleans real files before HM creates symlinks |
| `home.activation.installPhotoGIMP` (entryAfter writeBoundary) | Present | ✅ Intact — version-sentinel GIMP config copy |
| `home.activation.refreshPhotoGIMPDesktopIntegration` (entryAfter writeBoundary) | Present | ✅ Intact — gtk-update-icon-cache + update-desktop-database |
| `xdg.dataFile."icons/hicolor"` with `recursive = true` | Present | ✅ Intact — per-file symlinks for all icon sizes |
| `photogimp = pkgs.fetchFromGitHub { ... }` with correct hash | Present | ✅ Unchanged — hash `sha256-R9MMidsR2+...` preserved |
| `photogimpVersion = "3.0"` | Present | ✅ Unchanged |
| Options declaration `options.photogimp.enable` | Present | ✅ Intact |

---

### 5. `xdg.desktopEntries` Removal

**Result: PASS**

There is no `xdg.desktopEntries` reference anywhere in `home/photogimp.nix`. The old block has been fully removed and replaced with `xdg.dataFile."applications/org.gimp.GIMP.desktop"`. ✅

---

### 6. Module Structure

**Result: PASS**

The overall structure is:
```nix
{ config, lib, pkgs, ... }:
let
  photogimpVersion = "3.0";
  photogimp = pkgs.fetchFromGitHub { ... };
in
{
  options.photogimp.enable = lib.mkEnableOption "...";

  config = lib.mkIf config.photogimp.enable {
    home.activation.cleanupPhotogimpOrphanFiles = ...;
    home.activation.installPhotoGIMP = ...;
    home.activation.refreshPhotoGIMPDesktopIntegration = ...;
    xdg.dataFile."icons/hicolor" = { ... };
    xdg.dataFile."applications/org.gimp.GIMP.desktop" = { ... };
  };
}
```

All braces properly matched. The `config = lib.mkIf config.photogimp.enable { ... }` block is correctly closed. ✅

---

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 90% | A- |
| Best Practices | 97% | A |
| Functionality | 100% | A+ |
| Code Quality | 97% | A |
| Security | 100% | A+ |
| Performance | 100% | A+ |
| Consistency | 97% | A |
| Build Success | N/A | SKIPPED |

**Overall Grade: A (97%)**  
*(Build Success excluded from average; static review found no build-blocking issues)*

---

## Issues Summary

### CRITICAL
None.

### HIGH
None.

### LOW (Non-blocking spec deviations)

1. **Missing `Version=1.1`** in `.desktop` content.  
   Spec example includes it at line 3. Implementation omits it.  
   Impact: None — the FreeDesktop.org `Version` key is cosmetic and ignored by GLib, GNOME Shell, and all modern desktop environments.

2. **Missing `Keywords=GIMP;PhotoGIMP;graphic;design;illustration;painting;`** in `.desktop` content.  
   Spec example includes it as the final line. Implementation omits it.  
   Impact: Low — reduces GNOME Activities keyword search hits for "GIMP" and "PhotoGIMP". The `Name` and `GenericName` fields still provide adequate search coverage.

---

## Final Verdict

**PASS**

The implementation correctly resolves both root causes identified in the spec:
- **RC1 (Critical)**: `.desktop` now placed at `XDG_DATA_HOME/applications/` via `xdg.dataFile`, producing a file-level symlink that GFileMonitor detects reliably in a running GNOME session.
- **RC2 (High)**: `X-Flatpak=org.gimp.GIMP` is present, enabling GNOME Shell 46+ window-to-app matching.

All explicitly reviewed fields are correct. The two low-severity omissions (`Version=1.1`, `Keywords`) do not affect functionality and are not listed in the mandatory review checklist. No regressions. Module structure is valid. Build is expected to succeed pending live `nix flake check` confirmation.
