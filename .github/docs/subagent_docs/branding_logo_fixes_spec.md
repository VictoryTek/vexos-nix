# Specification: Branding Logo Fixes — GDM, GNOME About, Background Logo Extension

**Feature Name:** `branding_logo_fixes`
**Spec Path:** `.github/docs/subagent_docs/branding_logo_fixes_spec.md`
**Date:** 2026-03-26
**Status:** Draft

---

## 1. Current State Analysis

### 1.1 Files Read

| File | Key Observations |
|---|---|
| `modules/branding.nix` | Deploys pixmaps via `vexosLogos` runCommand. Sets GDM dconf logo to `/etc/vexos/gdm-logo.png` sourced from `system-logo-white.png`. No GNOME About page or Background Logo extension configuration. |
| `modules/gnome.nix` | Installs `gnomeExtensions.background-logo` in systemPackages (line 112). No dconf settings for the extension. |
| `home.nix` | Enables `background-logo@fedorahosted.org` in `enabled-extensions` (line 157). No dconf settings under `org/fedorahosted/background-logo-extension`. No os-release override. |
| `configuration.nix` | Imports `modules/branding.nix`. `system.stateVersion = "25.11"` (must NOT change). |
| `flake.nix` | Four outputs: `vexos-amd`, `vexos-nvidia`, `vexos-vm`, `vexos-intel`. All share `configuration.nix` via `commonModules`. |

### 1.2 Available Assets in `files/pixmaps/`

| Filename | Size (bytes) | Current Deployment |
|---|---|---|
| `vex.png` | 48,956 | Deployed as `vex.png` and `distributor-logo.png` in `share/pixmaps/` |
| `system-logo-white.png` | 21,912 | Deployed as `system-logo-white.png` in `share/pixmaps/`; also deployed to `/etc/vexos/gdm-logo.png` |
| `fedora-gdm-logo.png` | 7,745 | Deployed as `vex-gdm-logo.png` in `share/pixmaps/`; **NOT used for GDM login** |
| `fedora-logo-small.png` | 9,027 | Deployed as `vex-logo-small.png` in `share/pixmaps/` |
| `fedora-logo-sprite.png` | 21,912 | Deployed as `vex-logo-sprite.png` in `share/pixmaps/` |
| `fedora-logo-sprite.svg` | 139,310 | Deployed as `vex-logo-sprite.svg` in `share/pixmaps/` |
| `fedora-logo.png` | 425,219 | Deployed as `vex-logo.png` in `share/pixmaps/` |
| `fedora_logo_med.png` | 20,832 | Deployed as `vex-logo-med.png` in `share/pixmaps/` |
| `fedora_whitelogo_med.png` | 20,832 | Deployed as `vex-whitelogo-med.png` in `share/pixmaps/` |

### 1.3 Current GDM Logo Configuration

In `modules/branding.nix` (lines 48–63):
```nix
environment.etc."vexos/gdm-logo.png".source = ../files/pixmaps/system-logo-white.png;

programs.dconf.profiles.gdm = {
  enableUserDb = false;
  databases = [
    {
      settings = {
        "org/gnome/login-screen" = {
          logo = "/etc/vexos/gdm-logo.png";
        };
      };
    }
  ];
};
```

The dconf plumbing is correct. The problem is the **source file**: `system-logo-white.png` (21,912 bytes) has the exact same byte count as `fedora-logo-sprite.png` (21,912 bytes), strongly suggesting it is either the same file or a derivative. The intended GDM logo should be `fedora-gdm-logo.png` (7,745 bytes), which is a GDM-optimized smaller logo suitable for the login screen.

### 1.4 Current GNOME About Page Logo

NixOS generates `/etc/os-release` via the `nixos/modules/misc/version.nix` module. This file contains the line:
```
LOGO=nix-snowflake
```

The GNOME Settings About panel (`gnome-control-center`, `cc-info-overview-panel.c`) reads this value using `g_get_os_info("LOGO")` and passes it to `gtk_image_set_from_icon_name()`. This triggers GTK's icon theme lookup, which finds the `nix-snowflake` icon from the NixOS icons package — resulting in the NixOS snowflake logo appearing on the About page.

**No override exists** in the current configuration. The custom `distributor-logo.png` deployed to `share/pixmaps/` is never referenced because os-release points to `nix-snowflake`, not `distributor-logo`.

### 1.5 Current Background Logo Extension Configuration

The extension `background-logo@fedorahosted.org` is:
- **Installed**: `gnomeExtensions.background-logo` in `modules/gnome.nix` (line 112)
- **Enabled**: Listed in `enabled-extensions` in `home.nix` (line 157)
- **Not configured**: Zero dconf settings exist under `org/fedorahosted/background-logo-extension`

Without configuration, the extension uses its compiled-in defaults, which reference Fedora's logo paths (typically `/usr/share/fedora-logos/...`). These paths do not exist on NixOS, so the extension either shows nothing or falls back to a default GNOME logo.

---

## 2. Problem Definition

### Problem 1: GDM Login Screen Shows Wrong Logo

**What's wrong:** The GDM login screen logo source file (`/etc/vexos/gdm-logo.png`) is sourced from `files/pixmaps/system-logo-white.png`, which appears to be a `fedora-logo-sprite.png` variant (identical 21,912-byte size). The correct source should be `files/pixmaps/fedora-gdm-logo.png` (7,745 bytes) — a smaller, GDM-optimized logo.

**Root cause:** Incorrect `source` value in `environment.etc."vexos/gdm-logo.png"`.

### Problem 2: GNOME About Page Shows NixOS Logo

**What's wrong:** The GNOME Settings > About page displays the NixOS snowflake logo instead of the custom vexos branding. The system deploys `distributor-logo.png` to `share/pixmaps/`, but the About page reads the `LOGO` field from `/etc/os-release` which is set to `nix-snowflake` by the NixOS version module.

**Root cause:** No override of the `LOGO` field in `/etc/os-release`. The deployed `distributor-logo.png` icon is never referenced.

### Problem 3: Background Logo Extension Unconfigured

**What's wrong:** The GNOME Background Logo extension is installed and enabled but has no dconf configuration. It cannot find logos at its default (Fedora) paths on NixOS, so it displays nothing or a wrong fallback. The "Show for all backgrounds" toggle (`logo-always-visible`) is not enabled.

**Root cause:** Missing dconf settings under `org/fedorahosted/background-logo-extension` in `home.nix`.

---

## 3. Research Findings

### 3.1 GDM Login Screen Logo Mechanism

The GDM greeter reads the logo from the dconf key `org.gnome.login-screen.logo` (string: absolute file path to a PNG). The current dconf plumbing in `modules/branding.nix` is correct — the only fix needed is changing the source image file.

The `fedora-gdm-logo.png` file (7,745 bytes) is specifically designed for the GDM greeter context: small, optimized for the login screen header area. Source: Fedora Silverblue `fedora-logos` package conventions.

### 3.2 GNOME About Page Logo — os-release LOGO Field

**How GNOME reads it:**
1. `gnome-control-center` calls `g_get_os_info("LOGO")` (GLib API)
2. GLib parses `/etc/os-release` using `GKeyFile` internally
3. The returned icon name is passed to `gtk_image_set_from_icon_name()`
4. GTK resolves the icon via the icon theme lookup chain:
   - Current icon theme (e.g., Adwaita)
   - `hicolor` fallback theme
   - `$XDG_DATA_DIRS/pixmaps/` (legacy fallback)

**Override strategy:** Append a `LOGO=distributor-logo` line to `/etc/os-release` using `lib.mkAfter`. GLib's `GKeyFile` parser returns the **last** value when duplicate keys exist. The icon name `distributor-logo` will resolve to `distributor-logo.png` via the `share/pixmaps/` fallback path (already deployed by `vexosLogos`).

**NixOS implementation:**
```nix
environment.etc.os-release.text = lib.mkAfter "LOGO=distributor-logo";
```

`environment.etc.<name>.text` uses `types.lines` in NixOS, which supports priority-based merging. `lib.mkAfter` (priority 1500) appends after the NixOS-generated content (priority 100).

**Sources consulted:**
1. GLib `g_get_os_info()` — GLib reference documentation; uses `GKeyFile` for parsing
2. `GKeyFile` duplicate key behavior — GLib source: last value wins for `g_key_file_get_string()`
3. GTK4 `gtk_image_set_from_icon_name()` — GTK documentation; triggers full icon theme lookup
4. Icon theme specification (freedesktop.org) — `$XDG_DATA_DIRS/pixmaps/` is a valid fallback for unthemed icons
5. NixOS `nixos/modules/misc/version.nix` — generates `/etc/os-release` with `LOGO=nix-snowflake`
6. NixOS option types — `types.lines` supports `mkBefore`/`mkAfter` for string concatenation with priority ordering
7. gnome-control-center `panels/info-overview/cc-info-overview-panel.c` — reads LOGO from os-release, passes to `gtk_image_set_from_icon_name()`

### 3.3 GNOME Background Logo Extension — dconf Schema

The Background Logo extension (`background-logo@fedorahosted.org`) uses the gsettings schema `org.fedorahosted.background-logo-extension`, which maps to the dconf path `org/fedorahosted/background-logo-extension/`.

**Relevant dconf keys:**

| Key | Type | Default (Fedora) | Description |
|---|---|---|---|
| `logo-file` | string | `""` (or Fedora path) | Absolute path to the logo file for light backgrounds |
| `logo-file-dark` | string | `""` (or Fedora path) | Absolute path to the logo file for dark backgrounds |
| `logo-always-visible` | boolean | `false` | "Show for all backgrounds" — when `true`, logo appears regardless of wallpaper |
| `logo-opacity` | double | `1.0` | Opacity (0.0–1.0) |
| `logo-border` | uint32 | `70` | Margin/border in pixels from screen edge |
| `logo-position` | string | `"center"` | Logo position on the desktop |
| `logo-size` | double | `10.0` | Size factor (percentage of screen) |

**Logo file paths on NixOS:** The `vexosLogos` package deploys to `/run/current-system/sw/share/pixmaps/`. This path is stable across rebuilds (the `/run/current-system` symlink is atomically updated). Suitable for dconf string values.

**Recommended logo files for the extension:**
- Light mode: `/run/current-system/sw/share/pixmaps/vex-logo-sprite.svg` — scalable SVG, ideal for desktop rendering
- Dark mode: `/run/current-system/sw/share/pixmaps/system-logo-white.png` — white-on-transparent, designed for dark backgrounds

**Sources consulted:**
1. Background Logo extension source — `github:nickaroot/gnome-shell-extension-background-logo` (Fedora fork at `fedorahosted.org`)
2. Extension gsettings schema — `schemas/org.fedorahosted.background-logo-extension.gschema.xml`
3. Fedora default configuration — Fedora Workstation ships with pre-configured logo paths and `logo-always-visible = false`

---

## 4. Proposed Solutions

### 4.1 Fix 1: GDM Login Screen Logo

**File:** `modules/branding.nix`

**Change:** Replace the `environment.etc."vexos/gdm-logo.png".source` value.

**Before (line 48):**
```nix
environment.etc."vexos/gdm-logo.png".source = ../files/pixmaps/system-logo-white.png;
```

**After:**
```nix
environment.etc."vexos/gdm-logo.png".source = ../files/pixmaps/fedora-gdm-logo.png;
```

**Effect:** The GDM login screen will display the GDM-optimized logo (7,745 bytes) instead of the sprite logo (21,912 bytes). No dconf changes needed — the path `/etc/vexos/gdm-logo.png` remains the same.

### 4.2 Fix 2: GNOME About Page Logo

**File:** `modules/branding.nix`

**Change:** Add an `environment.etc.os-release.text` override using `lib.mkAfter` to append a `LOGO=distributor-logo` line after the NixOS-generated os-release content.

**Addition (after the existing `environment.etc."vexos/gdm-logo.png"` block, around line 49):**
```nix
# ── GNOME About page logo ────────────────────────────────────────────────
# NixOS sets LOGO=nix-snowflake in /etc/os-release.  GNOME Settings
# reads this field with g_get_os_info("LOGO") and resolves it as an icon
# name via gtk_image_set_from_icon_name().  GLib's GKeyFile parser returns
# the *last* value for duplicate keys, so appending overrides the default.
# The icon name "distributor-logo" resolves to share/pixmaps/distributor-logo.png
# (deployed by vexosLogos above) via the XDG pixmaps fallback path.
environment.etc.os-release.text = lib.mkAfter "LOGO=distributor-logo";
```

**Effect:** The GNOME Settings About page will display `distributor-logo.png` (which is `vex.png`, the custom vexos brand logo) instead of the NixOS snowflake.

### 4.3 Fix 3: Background Logo Extension Configuration

**File:** `home.nix`

**Change:** Add a dconf settings block for `org/fedorahosted/background-logo-extension` within the existing `dconf.settings` attrset.

**Addition (inside `dconf.settings`, after the existing extension settings blocks):**
```nix
"org/fedorahosted/background-logo-extension" = {
  logo-file         = "/run/current-system/sw/share/pixmaps/vex-logo-sprite.svg";
  logo-file-dark    = "/run/current-system/sw/share/pixmaps/system-logo-white.png";
  logo-always-visible = true;
};
```

**Effect:**
- The extension will display `vex-logo-sprite.svg` on light backgrounds and `system-logo-white.png` on dark backgrounds.
- "Show for all backgrounds" is enabled by default (`logo-always-visible = true`).
- The extension will find the files at the stable NixOS system path `/run/current-system/sw/share/pixmaps/`.

---

## 5. Implementation Steps

### Step 1: Modify `modules/branding.nix`

1. Change line 48 — update the GDM logo source:
   ```
   environment.etc."vexos/gdm-logo.png".source = ../files/pixmaps/fedora-gdm-logo.png;
   ```

2. Add the os-release LOGO override (new block after line 48):
   ```nix
   environment.etc.os-release.text = lib.mkAfter "LOGO=distributor-logo";
   ```

### Step 2: Modify `home.nix`

1. Add the Background Logo extension dconf settings inside the `dconf.settings` attrset, logically grouped with other extension settings (e.g., after the `org/gnome/shell/extensions/dash-to-dock` block):
   ```nix
   "org/fedorahosted/background-logo-extension" = {
     logo-file         = "/run/current-system/sw/share/pixmaps/vex-logo-sprite.svg";
     logo-file-dark    = "/run/current-system/sw/share/pixmaps/system-logo-white.png";
     logo-always-visible = true;
   };
   ```

### Step 3: Validate

1. Run `nix flake check` — confirm flake evaluation succeeds
2. Dry-build all targets:
   - `sudo nixos-rebuild dry-build --flake .#vexos-amd`
   - `sudo nixos-rebuild dry-build --flake .#vexos-nvidia`
   - `sudo nixos-rebuild dry-build --flake .#vexos-vm`
3. Verify `hardware-configuration.nix` is NOT tracked in git
4. Verify `system.stateVersion` has not changed

---

## 6. Dependencies

No new external dependencies required. All changes use:
- Existing NixOS module options (`environment.etc`, `programs.dconf`)
- Existing Home Manager dconf integration
- Assets already present in `files/pixmaps/`
- Packages already installed (`vexosLogos`, `gnomeExtensions.background-logo`)

---

## 7. Files Modified

| File | Change Type | Description |
|---|---|---|
| `modules/branding.nix` | Edit | Fix GDM logo source file; add os-release LOGO override |
| `home.nix` | Edit | Add Background Logo extension dconf settings |

---

## 8. Risks and Mitigations

### Risk 1: os-release Duplicate Key Parsing

**Risk:** The `lib.mkAfter` approach appends a second `LOGO=` line to `/etc/os-release`. Different parsers may handle duplicates differently (GLib takes last; systemd's parser may take first).

**Mitigation:** This only affects GNOME's About page, which uses GLib's `g_get_os_info()` (confirmed: takes last value via `GKeyFile`). Other consumers of `/etc/os-release` (e.g., `hostnamectl`) typically do not use the LOGO field, so inconsistent parsing is not a functional concern.

**Alternative if issues arise:** Deploy the vex logo as a `nix-snowflake` icon in `share/icons/hicolor/` to override the NixOS icon without modifying os-release. This requires handling potential file collisions with the NixOS icons package using `lib.hiPrio`.

### Risk 2: Background Logo Extension File Paths

**Risk:** The paths `/run/current-system/sw/share/pixmaps/...` are valid only after the `vexosLogos` package is in `environment.systemPackages`. If `modules/branding.nix` is not imported, the paths would be dangling.

**Mitigation:** `configuration.nix` already imports `modules/branding.nix`, and this import is shared across all host configurations via `flake.nix`. The paths are guaranteed to exist.

### Risk 3: GDM dconf Profile Conflict

**Risk:** The existing `programs.dconf.profiles.gdm` block might conflict with the GNOME NixOS module's own GDM dconf profile.

**Mitigation:** This risk was already accepted and documented in the original `logos_plymouth_spec.md`. The current configuration has been working without conflicts. No changes to the dconf profile plumbing are proposed — only the source image file changes.

### Risk 4: types.lines Merging Behavior

**Risk:** `lib.mkAfter` on `environment.etc.os-release.text` might not produce a clean newline-separated result if the NixOS-generated content does not end with a trailing newline.

**Mitigation:** NixOS's `types.lines` type joins values with `\n`. The NixOS version module's os-release text will be followed by a newline, then our appended `LOGO=distributor-logo` line. This produces valid os-release syntax.
