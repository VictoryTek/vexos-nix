# Specification: Branding Logo Fixes v2 — GNOME About Page & Background Logo Extension

**Feature Name:** `branding_logo_fixes_v2`
**Spec Path:** `.github/docs/subagent_docs/branding_logo_fixes_v2_spec.md`
**Date:** 2026-03-26
**Status:** Draft
**Supersedes:** `.github/docs/subagent_docs/branding_logo_fixes_spec.md` (v1 — partially failed)

---

## 1. Current State Analysis

### 1.1 Files Analyzed

| File | Key Observations |
|---|---|
| `modules/branding.nix` | Deploys pixmaps via `vexosLogos`. Contains failed `lib.mkAfter "LOGO=distributor-logo"` os-release override that does NOT fix the GNOME About page. |
| `home.nix` | Has `logo-file` dconf setting pointing to `vex-logo-sprite.svg` (should be `vex-logo-small.png`). |
| `modules/gnome.nix` | Installs `gnomeExtensions.background-logo` in systemPackages. |
| `configuration.nix` | Imports `modules/branding.nix`. `system.stateVersion = "25.11"` (MUST NOT change). |
| `flake.nix` | Four outputs: `vexos-amd`, `vexos-nvidia`, `vexos-vm`, `vexos-intel`. All share `configuration.nix` via `commonModules`. |

### 1.2 Available Assets in `files/pixmaps/`

| Filename | Current Deployment (in `vexosLogos`) |
|---|---|
| `vex.png` | `share/pixmaps/vex.png` + `share/pixmaps/distributor-logo.png` |
| `system-logo-white.png` | `share/pixmaps/system-logo-white.png` |
| `fedora-gdm-logo.png` | `share/pixmaps/vex-gdm-logo.png` |
| `fedora-logo-small.png` | `share/pixmaps/vex-logo-small.png` |
| `fedora-logo-sprite.png` | `share/pixmaps/vex-logo-sprite.png` |
| `fedora-logo-sprite.svg` | `share/pixmaps/vex-logo-sprite.svg` |
| `fedora-logo.png` | `share/pixmaps/vex-logo.png` |
| `fedora_logo_med.png` | `share/pixmaps/vex-logo-med.png` |
| `fedora_whitelogo_med.png` | `share/pixmaps/vex-whitelogo-med.png` |

### 1.3 Current GNOME About Page Logo (Issue 1 — STILL BROKEN)

**Current code in `modules/branding.nix`:**
```nix
environment.etc.os-release.text = lib.mkAfter "LOGO=distributor-logo";
```

**Observed behavior:** GNOME About page STILL shows the NixOS snowflake.

### 1.4 Current Background Logo Extension (Issue 2)

**Current dconf in `home.nix`:**
```nix
"org/fedorahosted/background-logo-extension" = {
  logo-file         = "/run/current-system/sw/share/pixmaps/vex-logo-sprite.svg";
  logo-file-dark    = "/run/current-system/sw/share/pixmaps/system-logo-white.png";
  logo-always-visible = true;
};
```

**Desired:** `logo-file` should point to `fedora-logo-small.png` (deployed as `vex-logo-small.png`).

---

## 2. Root Cause Analysis — Why the v1 os-release Fix Failed

### 2.1 How NixOS Generates os-release

NixOS generates `/etc/os-release` in `nixos/modules/misc/version.nix`. The key lines (from nixpkgs source):

```nix
# nixos/modules/misc/version.nix (simplified)
osReleaseContents = {
  NAME = "NixOS";
  ID = "nixos";
  # ...
  LOGO = "nix-snowflake";     # <-- the icon name GNOME reads
  # ...
};

environment.etc = {
  "os-release".text = attrsToText osReleaseContents;
};
```

The `.text` option uses `types.lines` (a `types.separatedString "\n"`), which supports `lib.mkAfter`. The v1 fix did correctly append `LOGO=distributor-logo` after the NixOS-generated content. GLib's `GKeyFile` parser returns the **last** value for duplicate keys, so `g_get_os_info("LOGO")` should return `"distributor-logo"`.

### 2.2 The Real Problem: GTK4 Icon Theme Resolution

The v1 fix assumed that deploying `distributor-logo.png` to `share/pixmaps/` would be sufficient for GTK to find it via `gtk_image_set_from_icon_name("distributor-logo")`. **This assumption was wrong.**

GNOME Settings (`gnome-control-center`) passes the `LOGO` value to GTK4's icon name API. GTK4's `GtkIconTheme` resolves icons through:

1. **Current icon theme** (e.g., Adwaita, kora) — structured `share/icons/<theme>/` directories
2. **hicolor fallback theme** — `share/icons/hicolor/` directories
3. **Legacy `share/pixmaps/` fallback** — **NOT reliably checked by GTK4** for icon-name lookups

The icon `distributor-logo` was deployed ONLY to `share/pixmaps/distributor-logo.png`. GTK4 does **not** reliably search `share/pixmaps/` during `GtkIconTheme` lookups (this is a GTK3→GTK4 behavior change). The icon was never found, and GNOME fell back to showing the NixOS snowflake from `nixos-icons`, which IS properly installed in the hicolor theme.

### 2.3 What nixos-icons Provides

The `nixos-icons` package (from `NixOS/nixos-artwork`) installs via its Makefile:

```makefile
sizes = 16 24 32 48 64 72 96 128 256 512 1024
theme = hicolor
category = apps

icons = \
  $(foreach size,$(sizes),$(size)x$(size)/$(category)/nix-snowflake.png) \
  scalable/$(category)/nix-snowflake.svg \
  $(foreach size,$(sizes),$(size)x$(size)/$(category)/nix-snowflake-white.png) \
  scalable/$(category)/nix-snowflake-white.svg
```

This produces:
- `share/icons/hicolor/scalable/apps/nix-snowflake.svg`
- `share/icons/hicolor/{16,24,32,48,64,72,96,128,256,512,1024}x{same}/apps/nix-snowflake.png`
- Same for `nix-snowflake-white`

These are installed into `/run/current-system/sw/share/icons/hicolor/` via `environment.systemPackages`. GTK4 finds these during icon theme lookups for the name `nix-snowflake`.

### 2.4 Summary

| Step | v1 Assumption | Reality |
|---|---|---|
| os-release LOGO override | `lib.mkAfter` appends `LOGO=distributor-logo` | ✅ Correct — `types.lines` merge works |
| GLib reads LOGO | `g_get_os_info("LOGO")` returns `"distributor-logo"` | ✅ Correct — GKeyFile last-value-wins |
| GTK4 finds the icon | `share/pixmaps/distributor-logo.png` is found | ❌ **WRONG** — GTK4 does not reliably check pixmaps for icon-name lookups |
| Result | Custom logo displays | ❌ Icon not found → GNOME falls back to `nix-snowflake` from hicolor |

---

## 3. Proposed Solutions

### 3.1 Fix 1: GNOME About Page Logo — Shadow `nix-snowflake` in hicolor

**Strategy:** Instead of changing the os-release LOGO field, **override what the `nix-snowflake` icon resolves to** by deploying the custom logo into the hicolor icon theme at all sizes that `nixos-icons` provides, using `lib.hiPrio` to win file conflicts.

This approach:
- Does not modify `/etc/os-release` (no duplicate keys, no parser inconsistencies)
- Properly integrates with GTK4's icon theme lookup
- Uses the standard Nix package priority mechanism (`lib.hiPrio`)
- Overrides at ALL sizes (raster + scalable) so GTK4 always finds the custom version

**File:** `modules/branding.nix`

**Changes:**

1. **Remove** the failed `environment.etc.os-release.text = lib.mkAfter "LOGO=distributor-logo";` line and its 5-line comment block (lines 50–57 in current file).

2. **Add** a new `vexosIcons` derivation that deploys `fedora-logo-sprite.png` as `nix-snowflake.png` at all raster sizes and `fedora-logo-sprite.svg` as `nix-snowflake.svg` at the scalable path:

```nix
# Hicolor icon-theme overrides for the nix-snowflake icon.
# The nixos-icons package installs the NixOS snowflake at every size
# in share/icons/hicolor/.  GNOME Settings reads LOGO=nix-snowflake
# from /etc/os-release and resolves it via GTK's icon-theme lookup.
# By deploying our brand logo under the same icon name and wrapping
# with lib.hiPrio, the vexos logo wins in the buildEnv file merge.
vexosIcons = pkgs.runCommand "vexos-icons" {} ''
  # Scalable SVG — GTK4 prefers this for icon-name lookups
  mkdir -p $out/share/icons/hicolor/scalable/apps
  cp ${../files/pixmaps/fedora-logo-sprite.svg} \
     $out/share/icons/hicolor/scalable/apps/nix-snowflake.svg

  # Raster PNGs at every size nixos-icons provides
  for size in 16 24 32 48 64 72 96 128 256 512 1024; do
    dir=$out/share/icons/hicolor/''${size}x''${size}/apps
    mkdir -p "$dir"
    cp ${../files/pixmaps/fedora-logo-sprite.png} "$dir/nix-snowflake.png"
  done
'';
```

3. **Update** `environment.systemPackages` to include the new icon package with higher priority:

```nix
environment.systemPackages = [ vexosLogos (lib.hiPrio vexosIcons) ];
```

`lib.hiPrio` sets `meta.priority = 4` (default is `5`). In Nix's `buildEnv`, the package with the lowest priority number wins when two packages provide the same file path. This means our `vexosIcons` files will override the corresponding `nixos-icons` files at:
- `share/icons/hicolor/scalable/apps/nix-snowflake.svg`
- `share/icons/hicolor/{16..1024}x{same}/apps/nix-snowflake.png`

Files from `nixos-icons` that we do NOT provide (e.g., `nix-snowflake-white.svg/png`) remain unaffected.

### 3.2 Fix 2: Background Logo Extension — Use `fedora-logo-small.png`

**File:** `home.nix`

**Change:** Update the `logo-file` dconf value from `vex-logo-sprite.svg` to `vex-logo-small.png`.

**Before:**
```nix
"org/fedorahosted/background-logo-extension" = {
  logo-file         = "/run/current-system/sw/share/pixmaps/vex-logo-sprite.svg";
  logo-file-dark    = "/run/current-system/sw/share/pixmaps/system-logo-white.png";
  logo-always-visible = true;
};
```

**After:**
```nix
"org/fedorahosted/background-logo-extension" = {
  logo-file         = "/run/current-system/sw/share/pixmaps/vex-logo-small.png";
  logo-file-dark    = "/run/current-system/sw/share/pixmaps/system-logo-white.png";
  logo-always-visible = true;
};
```

**Path verification:** `fedora-logo-small.png` is deployed by `vexosLogos` as:
```nix
cp ${../files/pixmaps/fedora-logo-small.png} $out/share/pixmaps/vex-logo-small.png
```
Runtime path: `/run/current-system/sw/share/pixmaps/vex-logo-small.png` ✅

---

## 4. Exact Code Changes

### 4.1 `modules/branding.nix` — Full Updated File

The `let` block should contain both `vexosLogos` (unchanged) and `vexosIcons` (new).

**Add `vexosIcons` derivation after `vexosLogos`** (inside the `let` block, before `in`):

```nix
  # Hicolor icon-theme overrides for the nix-snowflake icon.
  # The nixos-icons package installs the NixOS snowflake at every size
  # in share/icons/hicolor/.  GNOME Settings reads LOGO=nix-snowflake
  # from /etc/os-release and resolves it via GTK's icon-theme lookup.
  # By deploying our brand logo under the same icon name and wrapping
  # with lib.hiPrio, the vexos logo wins in the buildEnv file merge.
  vexosIcons = pkgs.runCommand "vexos-icons" {} ''
    # Scalable SVG — GTK4 prefers this for icon-name lookups
    mkdir -p $out/share/icons/hicolor/scalable/apps
    cp ${../files/pixmaps/fedora-logo-sprite.svg} \
       $out/share/icons/hicolor/scalable/apps/nix-snowflake.svg

    # Raster PNGs at every size nixos-icons provides
    for size in 16 24 32 48 64 72 96 128 256 512 1024; do
      dir=$out/share/icons/hicolor/''${size}x''${size}/apps
      mkdir -p "$dir"
      cp ${../files/pixmaps/fedora-logo-sprite.png} "$dir/nix-snowflake.png"
    done
  '';
```

**Update `environment.systemPackages`** (line 43 in current file):

Before:
```nix
  environment.systemPackages = [ vexosLogos ];
```

After:
```nix
  environment.systemPackages = [ vexosLogos (lib.hiPrio vexosIcons) ];
```

**Remove the os-release override block** (lines 50–57 in current file):

Remove these lines entirely:
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

### 4.2 `home.nix` — dconf Change

**Line 193** — change:
```nix
      logo-file         = "/run/current-system/sw/share/pixmaps/vex-logo-sprite.svg";
```
To:
```nix
      logo-file         = "/run/current-system/sw/share/pixmaps/vex-logo-small.png";
```

---

## 5. Implementation Steps

### Step 1: Edit `modules/branding.nix`

1. Add `vexosIcons` derivation inside the `let` block (after `vexosLogos`, before `in`)
2. Change `environment.systemPackages = [ vexosLogos ];` to `environment.systemPackages = [ vexosLogos (lib.hiPrio vexosIcons) ];`
3. Delete the 8-line os-release override block (comment + `environment.etc.os-release.text` line)

### Step 2: Edit `home.nix`

1. Change `logo-file` value from `vex-logo-sprite.svg` to `vex-logo-small.png`

### Step 3: Validate

1. Run `nix flake check`
2. Dry-build all targets:
   - `sudo nixos-rebuild dry-build --flake .#vexos-amd`
   - `sudo nixos-rebuild dry-build --flake .#vexos-nvidia`
   - `sudo nixos-rebuild dry-build --flake .#vexos-vm`
3. Verify `hardware-configuration.nix` is NOT tracked in git
4. Verify `system.stateVersion = "25.11"` has not changed

---

## 6. Dependencies

No new external dependencies. All changes use:
- Existing NixOS module options (`environment.systemPackages`)
- Existing Home Manager dconf integration
- Assets already present in `files/pixmaps/`
- `lib.hiPrio` — standard nixpkgs function, already available via `{ pkgs, lib, ... }:`
- `pkgs.runCommand` — already used for `vexosLogos`

---

## 7. Files Modified

| File | Change Type | Description |
|---|---|---|
| `modules/branding.nix` | Edit | Add `vexosIcons` derivation; update systemPackages with `lib.hiPrio`; remove failed os-release override |
| `home.nix` | Edit | Change `logo-file` from `vex-logo-sprite.svg` to `vex-logo-small.png` |

---

## 8. Risks and Mitigations

### Risk 1: `lib.hiPrio` File Conflict with `nixos-icons`

**Risk:** If `nixos-icons` changes its file layout in a future nixpkgs update (adds/removes sizes), our override may miss new sizes or conflict unexpectedly.

**Mitigation:** We deploy at ALL sizes that nixos-icons currently generates (16, 24, 32, 48, 64, 72, 96, 128, 256, 512, 1024 + scalable). If nixos-icons adds new sizes in the future, our package simply won't conflict at those new sizes — GTK would use the nixos-icons version there but prefer the scalable SVG (which we DO override) for rendering. If nixos-icons removes sizes, our package still installs at those sizes harmlessly (no conflict).

### Risk 2: SVG Sprite Rendering

**Risk:** `fedora-logo-sprite.svg` might be a sprite sheet (composite image with multiple logo variants) rather than a single logo. If deployed as `nix-snowflake.svg`, the GNOME About page would display the full sprite.

**Mitigation:** If the SVG renders incorrectly on the About page, the raster PNG versions at large sizes (256, 512, 1024) provide a fallback. Alternatively, replace `fedora-logo-sprite.svg` with a proper single-logo SVG in the `files/pixmaps/` directory. The PNG version (`fedora-logo-sprite.png`) is confirmed to be a single logo image suitable for display.

### Risk 3: Background Logo Extension Path Validity

**Risk:** The path `/run/current-system/sw/share/pixmaps/vex-logo-small.png` depends on `vexosLogos` being in `environment.systemPackages`.

**Mitigation:** `configuration.nix` unconditionally imports `modules/branding.nix`, which adds `vexosLogos` to systemPackages. This import is shared across all host configurations via `commonModules` in `flake.nix`. The path is guaranteed to exist on all builds.

### Risk 4: Removing os-release Override

**Risk:** Removing the `lib.mkAfter "LOGO=distributor-logo"` line means os-release keeps `LOGO=nix-snowflake`. Tools like `fastfetch` that read os-release LOGO for display purposes would still see `nix-snowflake`, but now the icon resolves to our custom image (because we override it in hicolor).

**Mitigation:** This is actually **better** than the v1 approach — all tools that resolve `nix-snowflake` as an icon will now show our custom image, and there are no duplicate keys in os-release. Tools that only display the LOGO string without icon resolution would show "nix-snowflake" as text, which is cosmetically neutral.

---

## 9. Research Sources

1. **NixOS `nixos/modules/misc/version.nix`** (nixpkgs main) — Confirms `LOGO = "nix-snowflake"` in `osReleaseContents` attrset, generated via `attrsToText` into `environment.etc."os-release".text`
2. **NixOS `nixos-artwork/icons/Makefile`** (NixOS/nixos-artwork) — Confirms exact sizes: 16, 24, 32, 48, 64, 72, 96, 128, 256, 512, 1024 for both `nix-snowflake` and `nix-snowflake-white`, plus scalable SVGs
3. **nixos-icons `package.nix`** (nixpkgs `pkgs/by-name/ni/nixos-icons/`) — Uses imagemagick for SVG→PNG conversion; `make install prefix=$out`
4. **Plymouth `boot.plymouth.logo`** default — Uses `${pkgs.nixos-icons}/share/icons/hicolor/48x48/apps/nix-snowflake-white.png`, confirming nixos-icons' hicolor layout
5. **`cavif` package test** — Uses `${nixos-icons}/share/icons/hicolor/512x512/apps/nix-snowflake.png`, confirming 512x512 raster exists
6. **GTK4 `GtkIconTheme` documentation** — Icon-name lookups search structured `share/icons/<theme>/` directories; `share/pixmaps/` is a legacy fallback not reliably checked in GTK4
7. **GLib `g_get_os_info()` and `GKeyFile`** — GKeyFile returns last value for duplicate keys; `g_get_os_info("LOGO")` reads from `/etc/os-release`
8. **Nix `lib.hiPrio` / `lib.setPrio`** — Sets `meta.priority = 4` (default `5`); lower number wins in `buildEnv` file conflict resolution
