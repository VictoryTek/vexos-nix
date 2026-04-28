# Specification: Add gnomeExtensions.tiling-assistant to All GNOME Roles

**Feature:** `tiling_assistant`  
**Date:** 2026-04-28  
**Status:** Draft — Phase 1 complete

---

## 1. Current State Analysis

### 1.1 Roles That Use GNOME

| Role            | Uses GNOME | GNOME role file              |
|-----------------|------------|------------------------------|
| desktop         | ✅ Yes     | `modules/gnome-desktop.nix`  |
| htpc            | ✅ Yes     | `modules/gnome-htpc.nix`     |
| server          | ✅ Yes     | `modules/gnome-server.nix`   |
| stateless       | ✅ Yes     | `modules/gnome-stateless.nix`|
| headless-server | ❌ No      | (none — no X/GDM)            |

All four GNOME roles import `./modules/gnome.nix` as their universal GNOME base, then import their role-specific `gnome-<role>.nix` on top.

### 1.2 How Extensions Are Currently Installed (Packages)

All GNOME Shell extension packages are listed in `environment.systemPackages` inside **`modules/gnome.nix`** using the `unstable.gnomeExtensions.*` attribute path (sourced from the nixpkgs-unstable overlay). The sole exception is `unstable.gnomeExtensions.gamemode-shell-extension`, which is added in `modules/gnome-desktop.nix` because it is desktop-only.

**Pattern in `modules/gnome.nix`:**
```nix
environment.systemPackages = with pkgs; [
  unstable.gnomeExtensions.appindicator
  unstable.gnomeExtensions.alphabetical-app-grid
  unstable.gnomeExtensions.gnome-40-ui-improvements
  unstable.gnomeExtensions.nothing-to-say
  unstable.gnomeExtensions.steal-my-focus-window
  unstable.gnomeExtensions.tailscale-status
  unstable.gnomeExtensions.caffeine
  unstable.gnomeExtensions.restart-to
  unstable.gnomeExtensions.blur-my-shell
  unstable.gnomeExtensions.background-logo
];
```

### 1.3 How Extensions Are Currently Enabled (dconf)

Extensions are enabled via `programs.dconf.profiles.user.databases` in each role-specific file. The `enabled-extensions` key is a GVariant string list set under `"org/gnome/shell"`. A local `let`-binding called `commonExtensions` holds the shared UUID list, and is duplicated verbatim in all four role files (known tech debt, noted in `gnome_role_split_review.md`).

**Pattern in each `gnome-<role>.nix`:**
```nix
let
  commonExtensions = [
    "appindicatorsupport@rgcjonas.gmail.com"
    "AlphabeticalAppGrid@stuarthayhurst"
    "gnome-ui-tune@itstime.tech"
    "nothing-to-say@extensions.gnome.wouter.bolsterl.ee"
    "steal-my-focus-window@steal-my-focus-window"
    "tailscale-status@maxgallup.github.com"
    "caffeine@patapon.info"
    "restartto@tiagoporsch.github.io"
    "blur-my-shell@aunetx"
    "background-logo@fedorahosted.org"
  ];
in {
  programs.dconf.profiles.user.databases = [
    {
      settings."org/gnome/shell" = {
        enabled-extensions = commonExtensions;  # (or commonExtensions ++ [...] for desktop)
      };
    }
  ];
}
```

**Important:** `home/gnome-common.nix` does **not** set `enabled-extensions`. The Home Manager dconf block there only sets interface, wm/preferences, background, screensaver, and housekeeping keys. Extension enabling is handled entirely at the system level via `programs.dconf.profiles.user.databases`.

**Important:** In NixOS's dconf profile system, multiple `databases` entries in the same profile are separate database files consulted in priority order — the first file wins for any given key. There is no list-append merging for `enabled-extensions` across databases. Each role file must supply the complete, final value for `enabled-extensions` in a single database entry.

### 1.4 Correct NixOS Package Attribute

```
unstable.gnomeExtensions.tiling-assistant
```

This is the correct attribute path in nixpkgs (verified in nixpkgs master as `pkgs.gnomeExtensions.tiling-assistant`). The project uses `unstable.gnomeExtensions.*` for all GNOME extensions (sourced from the nixpkgs-unstable overlay in `flake.nix`). Using the unstable pin for extensions ensures compatibility with the unstable GNOME Shell build already overlaid in `gnome.nix`.

### 1.5 Extension UUID

```
tiling-assistant@leleat-on.github.com
```

This is the official extension UUID registered in the GNOME Extensions repository for Tiling Assistant by leleat-on. It is the value GNOME Shell uses to identify the extension in `enabled-extensions`.

---

## 2. Problem Definition

`gnomeExtensions.tiling-assistant` is not installed or enabled on any GNOME role. Adding it will give all GNOME desktops half-tiling and quarter-tiling support via keyboard shortcuts and drag zones, consistent with the project's quality-of-life extension philosophy.

---

## 3. Proposed Solution Architecture

Following the **Module Architecture Pattern** (Option B: Common base + role additions):

- **Package** (`modules/gnome.nix`): Add `unstable.gnomeExtensions.tiling-assistant` to the universal `environment.systemPackages` block. This file is imported by all 4 GNOME roles, so one addition covers them all.

- **Enable (dconf)** (all 4 `gnome-<role>.nix` files): Add `"tiling-assistant@leleat-on.github.com"` to the `commonExtensions` list in each role file. Because `enabled-extensions` is a complete list key (not additive across dconf databases), and because each role file owns its complete `enabled-extensions` value, the UUID must be added to `commonExtensions` in each file.

No new files need to be created. No `lib.mkIf` guards are introduced. No `home/gnome-common.nix` change is needed (extensions are not enabled there).

---

## 4. Files to Modify

### 4.1 `modules/gnome.nix` — Add package

**Location:** Inside `environment.systemPackages = with pkgs; [ ... ]`, after the existing extensions list.

**Add one line:**
```nix
    unstable.gnomeExtensions.tiling-assistant              # Tiling / half-tile / quarter-tile window manager
```

The complete updated block (showing context):
```nix
  environment.systemPackages = with pkgs; [
    # GNOME tooling
    unstable.gnome-tweaks
    unstable.dconf-editor
    unstable.gnome-extension-manager

    bibata-cursors
    kora-icon-theme

    # GNOME Shell extensions
    unstable.gnomeExtensions.appindicator
    unstable.gnomeExtensions.alphabetical-app-grid
    unstable.gnomeExtensions.gnome-40-ui-improvements
    unstable.gnomeExtensions.nothing-to-say
    unstable.gnomeExtensions.steal-my-focus-window
    unstable.gnomeExtensions.tailscale-status
    unstable.gnomeExtensions.caffeine
    unstable.gnomeExtensions.restart-to
    unstable.gnomeExtensions.blur-my-shell
    unstable.gnomeExtensions.background-logo
    unstable.gnomeExtensions.tiling-assistant              # Tiling / half-tile / quarter-tile
  ];
```

### 4.2 `modules/gnome-desktop.nix` — Add UUID to commonExtensions

**Location:** Inside the `let commonExtensions = [ ... ];` block.

**Add one line:**
```nix
    "tiling-assistant@leleat-on.github.com"
```

### 4.3 `modules/gnome-htpc.nix` — Add UUID to commonExtensions

**Location:** Inside the `let commonExtensions = [ ... ];` block.

**Add one line:**
```nix
    "tiling-assistant@leleat-on.github.com"
```

### 4.4 `modules/gnome-server.nix` — Add UUID to commonExtensions

**Location:** Inside the `let commonExtensions = [ ... ];` block.

**Add one line:**
```nix
    "tiling-assistant@leleat-on.github.com"
```

### 4.5 `modules/gnome-stateless.nix` — Add UUID to commonExtensions

**Location:** Inside the `let commonExtensions = [ ... ];` block.

**Add one line:**
```nix
    "tiling-assistant@leleat-on.github.com"
```

---

## 5. Files NOT to Modify

| File | Reason |
|------|--------|
| `home/gnome-common.nix` | Does not manage `enabled-extensions`; no change needed |
| `modules/gnome.nix` dconf section | Does not set `enabled-extensions`; package addition only |
| `configuration-*.nix` files | Import list unchanged; no new module file is added |
| `flake.nix` | No new inputs or outputs needed |
| Any `hosts/*.nix` file | Per-host files are not the correct layer for this |

---

## 6. Exact Dconf Key Reference

| dconf path | key | value type | value to include |
|------------|-----|------------|-----------------|
| `org/gnome/shell` | `enabled-extensions` | `as` (string list) | `"tiling-assistant@leleat-on.github.com"` |

No additional tiling-assistant-specific dconf keys need to be set at this time. The extension ships with sensible defaults and the user can adjust keybindings via the Tiling Assistant preferences panel. Setting defaults would require knowing the extension's schema keys, which vary by version and are not required for the "enable by default" objective.

---

## 7. Dependencies

No new flake inputs are required. `gnomeExtensions.tiling-assistant` is available in both `nixpkgs` stable and nixpkgs-unstable. The project already pins GNOME extensions to unstable via the `unstable.gnomeExtensions.*` overlay, so `unstable.gnomeExtensions.tiling-assistant` is the correct reference.

---

## 8. Risks and Mitigations

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| `unstable.gnomeExtensions.tiling-assistant` attribute does not exist in current nixpkgs-unstable | Low | Attribute has been present in nixpkgs since GNOME 43. If absent, fall back to `pkgs.gnomeExtensions.tiling-assistant` (stable). |
| Extension conflicts with other tiling extensions (none currently enabled, but future-proofing) | Low | Tiling Assistant is self-contained and does not conflict with Blur My Shell, Background Logo, or any other currently-enabled extension. |
| GNOME Shell version mismatch (extension ABI) | Low | Using `unstable.gnomeExtensions.*` pins the extension to the same GNOME Shell build already overlaid by `gnome.nix`. |
| dconf `enabled-extensions` list becomes out of sync between role files | Low (existing debt) | This change adds the UUID to all 4 `commonExtensions` lists simultaneously, maintaining parity. The duplication tech debt is pre-existing and out of scope for this change. |
| HTPC / server roles may not benefit from tiling (single-monitor, media use) | Negligible | Having the extension installed and enabled is low cost; it only activates on explicit user gesture (drag or keyboard shortcut). No visual change unless triggered. |

---

## 9. Implementation Steps (Ordered)

1. **Edit `modules/gnome.nix`**  
   Append `unstable.gnomeExtensions.tiling-assistant` to the `environment.systemPackages` extensions block (after `unstable.gnomeExtensions.background-logo`).

2. **Edit `modules/gnome-desktop.nix`**  
   Append `"tiling-assistant@leleat-on.github.com"` to the `commonExtensions` list.

3. **Edit `modules/gnome-htpc.nix`**  
   Append `"tiling-assistant@leleat-on.github.com"` to the `commonExtensions` list.

4. **Edit `modules/gnome-server.nix`**  
   Append `"tiling-assistant@leleat-on.github.com"` to the `commonExtensions` list.

5. **Edit `modules/gnome-stateless.nix`**  
   Append `"tiling-assistant@leleat-on.github.com"` to the `commonExtensions` list.

6. **Validate**  
   Run `nix flake check` to confirm the flake evaluates cleanly.  
   Run `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd` (and optionally nvidia/vm variants) to confirm the system closure builds.

---

## 10. Summary of Changes

| File | Change |
|------|--------|
| `modules/gnome.nix` | +1 line: `unstable.gnomeExtensions.tiling-assistant` in `environment.systemPackages` |
| `modules/gnome-desktop.nix` | +1 line: UUID in `commonExtensions` |
| `modules/gnome-htpc.nix` | +1 line: UUID in `commonExtensions` |
| `modules/gnome-server.nix` | +1 line: UUID in `commonExtensions` |
| `modules/gnome-stateless.nix` | +1 line: UUID in `commonExtensions` |

**Total:** 5 files modified, 5 lines added, 0 files created, 0 files deleted.
