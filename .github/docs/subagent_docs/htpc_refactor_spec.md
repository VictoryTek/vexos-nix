# HTPC Configuration Refactor — Specification

**Feature Name:** htpc_refactor  
**Date:** 2026-04-15  
**Status:** DRAFT  

---

## 1. Overview / Problem Statement

The HTPC configuration (`configuration-htpc.nix`) currently inherits the full default Flatpak app list from `modules/flatpak.nix` and excludes only a small set of apps. Several additional apps in the default list are irrelevant to a streaming HTPC (gaming launchers, developer tools), and three HTPC-specific Flatpak apps are missing. Additionally, the Ghostty terminal is available on the desktop via home-manager but is absent from HTPC because HTPC uses `minimalModules` (no home-manager). This spec covers the minimal, targeted changes required to make the HTPC app set accurate and complete.

---

## 2. Current State Analysis

### 2.1 configuration-htpc.nix

- Imports: `gnome.nix`, `audio.nix`, `gpu.nix`, `flatpak.nix`, `network.nix`, `packages.nix`, `branding.nix`, `system.nix`
- Does NOT import: `gaming.nix`, `development.nix`, `virtualization.nix` (correct — none needed)
- `vexos.flatpak.excludeApps` currently contains:
  - `"org.gimp.GIMP"`
  - `"com.ranfdev.DistroShelf"`
  - `"com.mattjakeman.ExtensionManager"`
  - `"com.vysp3r.ProtonPlus"`
- `environment.systemPackages`: `[ pkgs.kora-icon-theme ]`
- Has a dconf system-level setting for `icon-theme = "kora"`
- Does NOT have ghostty in `environment.systemPackages`
- Does NOT set `vexos.flatpak.extraApps` (option does not yet exist)

### 2.2 modules/flatpak.nix

- Provides option: `vexos.flatpak.excludeApps` (listOf string, default `[]`)
- Does NOT yet provide: `vexos.flatpak.extraApps`
- `defaultApps` list (full, alphabetical):
  - `app.zen_browser.zen`
  - `com.bitwarden.desktop`
  - `com.github.tchx84.Flatseal`
  - `com.github.wwmm.easyeffects`
  - `com.rustdesk.RustDesk`
  - `com.simplenote.Simplenote`
  - `com.usebottles.bottles`
  - `com.vysp3r.ProtonPlus`
  - `io.github.flattool.Warehouse`
  - `io.github.kolunmi.Bazaar`
  - `io.github.pol_rivero.github-desktop-plus`
  - `io.missioncenter.MissionCenter`
  - `it.mijorus.gearlever`
  - `net.lutris.Lutris`
  - `org.gnome.World.PikaBackup`
  - `org.onlyoffice.desktopeditors`
  - `org.prismlauncher.PrismLauncher`
  - `org.pulseaudio.pavucontrol`

### 2.3 home.nix

- Imports `home/photogimp.nix`; sets `photogimp.enable = true`
- Installs `ghostty` via `home.packages` in home-manager
- HTPC uses `minimalModules` — home-manager is NOT applied to HTPC
- Therefore: photogimp and home-manager ghostty are already absent from HTPC (no action needed)

### 2.4 modules/gnome.nix

- Shared by both desktop and HTPC
- Installs `unstable.gnome-extension-manager` as a system package
- Removes `org.gnome.Extensions.desktop` via overlay
- No changes needed in this file

---

## 3. Proposed Changes

### 3.1 modules/flatpak.nix — Add `extraApps` option

**File:** `modules/flatpak.nix`

Add a new NixOS module option:

```nix
vexos.flatpak.extraApps = mkOption {
  type = types.listOf types.str;
  default = [];
  description = "Additional Flatpak app IDs to install beyond the default list.";
};
```

The activation script (or equivalent mechanism already used for `defaultApps` and `excludeApps`) must be updated to also install all entries in `extraApps`. The effective install list becomes:

```
(defaultApps minus excludeApps) union extraApps
```

Specifically, in the existing activation logic, after filtering `defaultApps` by `excludeApps`, append `config.vexos.flatpak.extraApps` to the list of apps to install.

### 3.2 configuration-htpc.nix — excludeApps additions

**File:** `configuration-htpc.nix`

Extend `vexos.flatpak.excludeApps` to add the following three entries (in addition to the four already present):

| App ID | Reason for exclusion |
|---|---|
| `net.lutris.Lutris` | Gaming launcher — not needed on a streaming HTPC |
| `org.prismlauncher.PrismLauncher` | Minecraft launcher — not needed on a streaming HTPC |
| `io.github.pol_rivero.github-desktop-plus` | Desktop Plus (green puzzle icon) — not useful on a streaming HTPC |

Full updated `excludeApps` list after change:

```nix
vexos.flatpak.excludeApps = [
  "com.mattjakeman.ExtensionManager"
  "com.ranfdev.DistroShelf"
  "com.vysp3r.ProtonPlus"
  "io.github.pol_rivero.github-desktop-plus"
  "net.lutris.Lutris"
  "org.gimp.GIMP"
  "org.prismlauncher.PrismLauncher"
];
```

### 3.3 configuration-htpc.nix — extraApps (new)

**File:** `configuration-htpc.nix`

Add `vexos.flatpak.extraApps` with three HTPC-specific Flatpak apps:

```nix
vexos.flatpak.extraApps = [
  "com.github.unrud.VideoDownloader"
  "io.freetubeapp.FreeTube"
  "tv.plex.PlexDesktop"
];
```

### 3.4 configuration-htpc.nix — Add ghostty to systemPackages

**File:** `configuration-htpc.nix`

Since HTPC does not use home-manager, `ghostty` must be added to `environment.systemPackages` directly. Update the existing list:

```nix
environment.systemPackages = with pkgs; [
  ghostty
  kora-icon-theme
];
```

---

## 4. Implementation Steps

1. **Edit `modules/flatpak.nix`:**
   - Declare the `vexos.flatpak.extraApps` option (type: `listOf str`, default: `[]`)
   - Update the activation/install logic to include `extraApps` entries in the effective install set

2. **Edit `configuration-htpc.nix`:**
   - Add `"io.github.pol_rivero.github-desktop-plus"`, `"net.lutris.Lutris"`, and `"org.prismlauncher.PrismLauncher"` to `vexos.flatpak.excludeApps`
   - Add `vexos.flatpak.extraApps` with `"com.github.unrud.VideoDownloader"`, `"io.freetubeapp.FreeTube"`, and `"tv.plex.PlexDesktop"`
   - Add `pkgs.ghostty` to `environment.systemPackages`

3. **Verify no other host config is affected:**
   - `extraApps` defaults to `[]` — desktop hosts are unaffected
   - `excludeApps` changes are local to `configuration-htpc.nix` — desktop hosts are unaffected

4. **Run preflight validation:**
   - `scripts/preflight.sh` must pass
   - `nix flake check` must pass
   - Dry-build for all relevant targets must succeed

---

## 5. Files to Be Modified

| File | Change |
|---|---|
| `modules/flatpak.nix` | Add `vexos.flatpak.extraApps` option and wire it into install logic |
| `configuration-htpc.nix` | Extend `excludeApps`, add `extraApps`, add `ghostty` to `systemPackages` |

No other files require modification.

---

## 6. Items Explicitly Out of Scope

The following were analyzed and confirmed to require no changes:

| Item | Reason |
|---|---|
| `com.ranfdev.DistroShelf` | Already in `excludeApps` |
| `com.vysp3r.ProtonPlus` | Already in `excludeApps` |
| `org.gimp.GIMP` | Already in `excludeApps` |
| `com.mattjakeman.ExtensionManager` | Already in `excludeApps` |
| distrobox | Lives in `gaming.nix` system packages; `gaming.nix` is not imported by HTPC |
| photogimp | Applied via home-manager; HTPC has no home-manager — already absent |
| `gaming.nix` import | Already not present in HTPC |
| `development.nix` import | Already not present in HTPC |
| `modules/gnome.nix` | Shared module; no HTPC-specific changes needed |

---

## 7. Risks and Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| `extraApps` logic interacts incorrectly with `excludeApps` | Low | Implement as additive append after exclusion filter; write clear logic comment |
| `ghostty` package name differs between stable/unstable nixpkgs | Low | Confirm `pkgs.ghostty` resolves correctly; if not, use `pkgs.unstable.ghostty` |
| Flatpak IDs for new apps are incorrect or changed upstream | Low | IDs are well-known; verify against Flathub before implementation |
| Dry-build fails due to unresolved package | Low | Preflight dry-build will catch this before push |
| Desktop hosts inadvertently install extraApps entries | None | Default is `[]`; only `configuration-htpc.nix` sets a non-empty value |
