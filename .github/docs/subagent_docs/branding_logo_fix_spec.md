# Spec: GNOME About Logo Fix (branding_logo_fix)

**Date:** 2026-03-26  
**Status:** READY FOR IMPLEMENTATION  
**File to modify:** `modules/branding.nix`

---

## 1. Current State Analysis

### `modules/branding.nix` — `vexosIcons` derivation

```nix
vexosIcons = pkgs.runCommand "vexos-icons" {} ''
  mkdir -p $out/share/icons/hicolor/scalable/apps
  cp ... nix-snowflake.svg

  for size in 16 24 32 48 64 72 96 128 256 512 1024; do
    dir=$out/share/icons/hicolor/${size}x${size}/apps
    mkdir -p "$dir"
    cp ... "$dir/nix-snowflake.png"
  done
'';
```

**What it produces in the Nix store:**
```
share/icons/hicolor/scalable/apps/nix-snowflake.svg
share/icons/hicolor/16x16/apps/nix-snowflake.png
...
share/icons/hicolor/1024x1024/apps/nix-snowflake.png
```

**What it is MISSING:**
- `share/icons/hicolor/index.theme`  ← required by `gtk-update-icon-cache`
- `share/icons/hicolor/icon-theme.cache`  ← the critical missing file

### `modules/gnome.nix`

Does NOT add `nixos-icons` explicitly. `nixos-icons` enters the closure
transitively via `services.desktopManager.gnome.enable = true` in the NixOS
GNOME module at `nixos/modules/services/desktop-managers/gnome.nix`.

### `nixos-icons` package (nixpkgs 25.11)

Ships at build time:
```
share/icons/hicolor/scalable/apps/nix-snowflake.svg
share/icons/hicolor/16x16/apps/nix-snowflake.png
...
share/icons/hicolor/icon-theme.cache      ← THIS FILE EXISTS
share/icons/hicolor/index.theme           ← THIS FILE EXISTS
```

---

## 2. Problem Definition

GNOME About (`gnome-control-center` → System → About) reads `LOGO=nix-snowflake`
from `/etc/os-release` and resolves it through GTK's themed icon lookup chain.

GTK icon lookup for performance reasons reads `icon-theme.cache` first when it
exists in the hicolor theme directory. The cache contains a direct mapping of
icon name → filename within the package's store path.

**In the NixOS buildEnv merge at `/run/current-system/sw/`:**

| File | `vexosIcons` provides? | `nixos-icons` provides? | Winner (hiPrio) |
|------|----------------------|------------------------|-----------------|
| `share/icons/hicolor/scalable/apps/nix-snowflake.svg` | ✔ | ✔ | `vexosIcons` ✔ |
| `share/icons/hicolor/NNxNN/apps/nix-snowflake.png`    | ✔ | ✔ | `vexosIcons` ✔ |
| `share/icons/hicolor/icon-theme.cache`                | ✘ | ✔ | `nixos-icons` ✘ |
| `share/icons/hicolor/index.theme`                     | ✘ | ✔ | `nixos-icons` ✘ |

`lib.hiPrio` only arbitrates between files that **both** packages provide.
Because `vexosIcons` provides **no** `icon-theme.cache`, there is no conflict
to resolve — `nixos-icons`' cache is the only one and it wins unconditionally.

GTK reads the cache, finds `nix-snowflake` mapped to the **`nixos-icons` store
path**, and returns the NixOS snowflake. The correctly overridden PNG/SVG files
that `vexosIcons` installed are on disk but **never consulted** because the
cache bypasses file-system traversal.

---

## 3. Root Cause (Primary Diagnosis)

> **`vexosIcons` does not generate `icon-theme.cache`. The `nixos-icons` cache
> file is the sole `icon-theme.cache` in the merged system profile and GTK uses
> it to resolve `nix-snowflake`, returning the NixOS snowflake paths and
> bypassing the overridden vexos logos entirely. `lib.hiPrio` cannot help
> because priority only applies to conflicting (same-path) files.**

---

## 4. Proposed Fix

### Fix A — Primary (Required): Generate `icon-theme.cache` in `vexosIcons`

Add `nativeBuildInputs = [ pkgs.gtk3 ]` so that `gtk-update-icon-cache` is
available during the `runCommand` build. Copy `hicolor/index.theme` from
`pkgs.hicolor-icon-theme` (required by `gtk-update-icon-cache`), then run the
cache generator. Because `vexosIcons` now provides its own `icon-theme.cache`,
`lib.hiPrio` arbitrates the conflict and our cache (pointing at the vexos logo
store paths) wins.

### Fix B — Belt-and-Suspenders (Recommended): Override `LOGO=` in os-release

Set `LOGO=` to an **absolute filesystem path** instead of a themed icon name.
This bypasses GTK icon-theme lookup entirely — GNOME About falls back to
loading the file directly when the value starts with `/`. This is the most
reliable long-term fix; it is immune to any future cache invalidation race.

NixOS generates `/etc/os-release` from the `system.nixos` module but does not
currently (25.11) provide a `distroLogoPath` option. The correct approach is
`environment.etc."os-release".text` composed with `lib.mkOverride`, or using
`environment.etc."vexos-os-release-logo"` with a systemd tmpfile that appends.
The simplest correct NixOS idiom is using `environment.etc."os-release"` with
the NixOS-generated content plus an appended override via `lib.mkAfter` on the
`text` attribute — **however** this attribute is `lib.mkDefault`-set by the
system module, so `lib.mkForce` is needed.

In practice the cleanest solution is to write a small activation script or use
a `systemd.tmpfiles` rule to patch the `LOGO=` line in-place after generation,
since `environment.etc."os-release"` is a generated symlink target that cannot
be trivially appended to.

**Simplest reliable approach for Fix B:** create a separate
`/etc/vexos/os-release-logo` file and use a systemd service that sets
`LOGO=/run/current-system/sw/share/pixmaps/vex-logo-sprite.png` in os-release
via `sed` in an activation script.

---

## 5. Exact Nix Code

### Replace the `vexosIcons` let-binding in `modules/branding.nix`

**Before:**
```nix
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

**After:**
```nix
vexosIcons = pkgs.runCommand "vexos-icons" {
  nativeBuildInputs = [ pkgs.gtk3 ];
} ''
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

  # Copy hicolor/index.theme — required by gtk-update-icon-cache
  cp ${pkgs.hicolor-icon-theme}/share/icons/hicolor/index.theme \
     $out/share/icons/hicolor/index.theme

  # Generate icon-theme.cache so that lib.hiPrio arbitrates the conflict
  # with nixos-icons' cache. Without this file, nixos-icons' cache is the
  # only one in the merged buildEnv profile and GTK resolves nix-snowflake
  # to the NixOS snowflake store paths, bypassing our overridden logos.
  gtk-update-icon-cache -f -t $out/share/icons/hicolor
'';
```

No other changes to `branding.nix` are required. The `lib.hiPrio` wrapping and
`environment.systemPackages` line remain unchanged.

### Optional Fix B — activation script to override LOGO= in os-release

Add inside the `{ ... }:` attrset in `modules/branding.nix`:

```nix
# Override LOGO= in /etc/os-release to an absolute path.
# This bypasses GTK themed icon lookup entirely: GNOME About loads the
# file directly when LOGO starts with '/', independently of icon caches.
system.activationScripts.vexosLogoOsRelease = {
  text = ''
    if grep -q "^LOGO=" /etc/os-release 2>/dev/null; then
      ${pkgs.gnused}/bin/sed -i \
        's|^LOGO=.*|LOGO=/run/current-system/sw/share/pixmaps/vex-logo-sprite.png|' \
        /etc/os-release
    else
      echo "LOGO=/run/current-system/sw/share/pixmaps/vex-logo-sprite.png" \
        >> /etc/os-release
    fi
  '';
  deps = [];
};
```

> **Note on Fix B:** This is belt-and-suspenders. Fix A alone is sufficient if
> the icon cache is generated correctly. Fix B is recommended for defence in
> depth because activation scripts run on every `nixos-rebuild switch` and the
> absolute path is immune to any future caching regressions. However, it uses a
> mutable activation script which some operators prefer to avoid. Implement at
> discretion.

---

## 6. Implementation Steps

1. Open `modules/branding.nix`.
2. Replace the `vexosIcons = pkgs.runCommand "vexos-icons" {} ''` line with
   the `vexosIcons = pkgs.runCommand "vexos-icons" { nativeBuildInputs = [ pkgs.gtk3 ]; } ''` form shown above.
3. Insert the three new lines inside the build script (copy index.theme + run
   `gtk-update-icon-cache`) **before the closing `''`** of the derivation.
4. Optionally add the `system.activationScripts.vexosLogoOsRelease` block to
   the module's returned attrset (after the existing `programs.dconf.profiles.gdm`
   block).
5. Validate with `nix flake check`.
6. Dry-build all three outputs:
   - `sudo nixos-rebuild dry-build --flake .#vexos-amd`
   - `sudo nixos-rebuild dry-build --flake .#vexos-nvidia`
   - `sudo nixos-rebuild dry-build --flake .#vexos-vm`
7. Apply with `sudo nixos-rebuild switch --flake .#<target>`.
8. Open GNOME Settings → About Device and confirm the vexos logo is shown.

---

## 7. Dependencies

| Package | Role | Already in nixpkgs 25.11? |
|---------|------|--------------------------|
| `pkgs.gtk3` | Provides `gtk-update-icon-cache` binary (nativeBuildInput only — not in systemPackages) | Yes |
| `pkgs.hicolor-icon-theme` | Provides `index.theme` copied into derivation | Yes |
| `pkgs.gnused` | Optional: used by Fix B activation script | Yes |

No new flake inputs required.

---

## 8. Risks and Mitigations

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| `gtk3` is a heavy nativeBuildInput for a small `runCommand` | Low — build-time only, not in closure | Acceptable; `gtk-update-icon-cache` is part of gtk3 and there is no lighter package shipping it in nixpkgs 25.11 |
| Future `nixos-icons` update adds more sizes not covered | Low | The cache is regenerated from whatever sizes `vexosIcons` installs; missing sizes fall through to file-system scan rather than using `nixos-icons` cache entries |
| Activation script (Fix B) races with os-release generation | Negligible — activation scripts run after all etc files are written | `deps = []` is correct; no ordering dependency needed |
| `vex-logo-sprite.png` is a JPEG-like raster, not SVG — may look blurry at 1× | Cosmetic | Supply a scalable SVG as primary (already done); PNG is fallback |

---

## 9. Files to Modify

- `modules/branding.nix` — primary change (Fix A required, Fix B optional)

No other files require modification for this fix.
