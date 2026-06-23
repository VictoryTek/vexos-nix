---
name: creality_print_appimage
description: Add Creality Print v7.1.0 as a custom AppImage derivation, register it under pkgs.vexos, add it to the 3D print module, and place it in the GNOME 3D app folder.
metadata:
  type: project
---

# Creality Print AppImage — Specification

## 1. Current State

- `modules/3d-print.nix` installs Blender and OrcaSlicer via `vexos.flatpak.extraApps`.
- The GNOME 3D app folder is defined in two places:
  - `modules/gnome-desktop.nix` — system dconf profile (defaults): **missing "3D" in `folder-children`** (gap)
  - `home-desktop.nix` (lines 163–212) — first-run stamp-gated systemd service: correctly includes "3D" with Blender and OrcaSlicer
- Creality Print is **not on Flathub** and **not in nixpkgs** (verified 2026-06-23).
- Creality provides an official AppImage from GitHub releases.

## 2. Problem Definition

Add Creality Print v7.1.0 as a managed system package so it:
1. Appears in `environment.systemPackages` (available system-wide)
2. Shows up in the GNOME 3D app folder alongside Blender and OrcaSlicer
3. Is packaged consistently with the existing `pkgs/vexos.*` pattern

**Update caveat:** This is an AppImage derivation with a pinned URL+hash. Updates require a manual version bump in `pkgs/creality-print/default.nix` per release. This is the only viable option since Creality Print is not on Flathub.

## 3. Upstream Details

- **Version:** 7.1.0 (build 7.1.0.4414)
- **Release tag:** `v7.1.0`
- **AppImage URL (ubuntu2004 — preferred for broader glibc compatibility):**
  `https://github.com/CrealityOfficial/CrealityPrint/releases/download/v7.1.0/CrealityPrint_ubuntu2004-V7.1.0.4414-x86_64-Release.AppImage`
- **License:** Unfree (proprietary; Creality's own slicer)
- **Desktop entry name:** `CrealityPrint.desktop` (standard AppImage convention; verify on first build — see §6)

## 4. Proposed Solution

### 4.1 New file: `pkgs/creality-print/default.nix`

Use `appimageTools.wrapType2` — the standard nixpkgs pattern for squashfs-based AppImages.
Use `lib.fakeHash` as the placeholder (same pattern as `pkgs/kiji-proxy/default.nix`).
First build will fail with the correct hash in the error output; paste it in.

```nix
{ lib, appimageTools, fetchurl }:

appimageTools.wrapType2 {
  pname   = "creality-print";
  version = "7.1.0.4414";

  src = fetchurl {
    url  = "https://github.com/CrealityOfficial/CrealityPrint/releases/download/v7.1.0/CrealityPrint_ubuntu2004-V7.1.0.4414-x86_64-Release.AppImage";
    hash = lib.fakeHash;
  };

  meta = {
    description = "Creality's official slicer for FDM 3D printers";
    homepage    = "https://github.com/CrealityOfficial/CrealityPrint";
    license     = lib.licenses.unfree;
    platforms   = [ "x86_64-linux" ];
    maintainers = [];
  };
}
```

### 4.2 Modify: `pkgs/default.nix`

Add under the `vexos` namespace:
```nix
creality-print = final.callPackage ./creality-print { };
```

### 4.3 Modify: `modules/3d-print.nix`

Add `pkgs` to the module arguments and add `environment.systemPackages`:
```nix
{ pkgs, ... }:
{
  vexos.flatpak.extraApps = [
    "org.blender.Blender"
    "com.orcaslicer.OrcaSlicer"
  ];

  environment.systemPackages = [
    pkgs.vexos.creality-print
  ];
}
```

### 4.4 Modify: `modules/gnome-desktop.nix`

Two changes:
1. Add `"3D"` to `folder-children` (fixing an existing gap — the first-run service already includes it, but the system dconf default does not)
2. Add the 3D folder definition with all three apps

```nix
"org/gnome/desktop/app-folders" = {
  folder-children = [ "Games" "Game Utilities" "Office" "3D" "Utilities" "System" ];
};

"org/gnome/desktop/app-folders/folders/3D" = {
  name = "3D";
  apps = [
    "org.blender.Blender.desktop"
    "com.orcaslicer.OrcaSlicer.desktop"
    "CrealityPrint.desktop"
  ];
};
```

### 4.5 Modify: `home-desktop.nix`

Add `CrealityPrint.desktop` to the 3D folder in the first-run stamp-gated service (line ~197):
```bash
$D write /org/gnome/desktop/app-folders/folders/"3D"/apps \
  "['org.blender.Blender.desktop', 'com.orcaslicer.OrcaSlicer.desktop', 'CrealityPrint.desktop']"
```

Also bump the stamp version from `v3` → `v4` so existing installs re-run the service with the updated folder layout.

## 5. Implementation Steps

| Step | Action | Verify |
|------|--------|--------|
| 1 | Create `pkgs/creality-print/default.nix` | File exists, uses `appimageTools.wrapType2` |
| 2 | Add entry to `pkgs/default.nix` | `vexos.creality-print` present |
| 3 | Update `modules/3d-print.nix` | Adds `pkgs` arg + `systemPackages` |
| 4 | Update `modules/gnome-desktop.nix` | "3D" in folder-children; 3D folder definition added |
| 5 | Update `home-desktop.nix` | CrealityPrint.desktop in 3D apps list; stamp bumped to v4 |
| 6 | Run `nix flake show --impure` | Exit 0, flake structure valid |
| 7 | Run `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd` | Exit 0 (note: fails until hash is filled in — expected) |

## 6. Hash Placeholder — Required Manual Step

Because this machine is Windows-based and cannot run Nix commands, `lib.fakeHash` is used as a placeholder. **Before `nixos-rebuild` can succeed**, the hash must be filled in on the NixOS host:

```bash
# On the NixOS host, after pulling the branch:
nix build --impure .#vexos.packages.x86_64-linux.creality-print 2>&1 | grep "got:"
# Copy the "got: sha256-..." value and replace lib.fakeHash in pkgs/creality-print/default.nix
```

Or using prefetch:
```bash
nix-prefetch-url \
  https://github.com/CrealityOfficial/CrealityPrint/releases/download/v7.1.0/CrealityPrint_ubuntu2004-V7.1.0.4414-x86_64-Release.AppImage
# Then: nix hash to-sri --type sha256 <result>
```

## 7. Desktop Entry Name Verification

AppImages embed their own `.desktop` file. If the GNOME app folder entry doesn't work, verify the actual filename:
```bash
# After building, extract and check:
appimage-run /run/current-system/sw/bin/creality-print --appimage-extract
ls squashfs-root/*.desktop
```
If it differs from `CrealityPrint.desktop`, update both `modules/gnome-desktop.nix` and `home-desktop.nix`.

## 8. Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| Hash placeholder causes dry-build to fail | Expected; documented above. dry-build in Phase 3 will fail — noted as acceptable for this specific case since the AppImage can't be fetched on this machine |
| Wrong desktop entry name | §7 verification step; easy one-line fix after first install |
| AppImage requires FUSE | `appimageTools.wrapType2` handles this by extracting at build time rather than mounting |
| Unfree license | Must set `nixpkgs.config.allowUnfree = true` — check that this is already set system-wide |

## 9. Modified Files

- `pkgs/creality-print/default.nix` (new)
- `pkgs/default.nix`
- `modules/3d-print.nix`
- `modules/gnome-desktop.nix`
- `home-desktop.nix`
