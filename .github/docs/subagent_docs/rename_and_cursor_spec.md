# Specification: Rename configuration.nix + Bibata-Modern-Classic Cursor
**Feature Name:** `rename_and_cursor`
**Date:** 2026-04-17
**Status:** Draft

---

## 1. Current State Analysis

### 1.1 Project Structure (Roles and Configuration Files)

| Role | Configuration File | Home File |
|---|---|---|
| desktop | `configuration.nix` | `home-desktop.nix` |
| htpc | `configuration-htpc.nix` | `home-htpc.nix` |
| server | `configuration-server.nix` | `home-server.nix` |
| stateless | `configuration-stateless.nix` | `home-stateless.nix` |

The desktop role's top-level configuration file is anomalous. All other roles follow the `configuration-<role>.nix` pattern. `configuration.nix` should be `configuration-desktop.nix`.

### 1.2 All References to `configuration.nix`

The following files reference `configuration.nix` by path or name and require changes:

#### Hard wiring (import paths — will cause build failure if not updated):
| File | Line | Reference | Type |
|---|---|---|---|
| `hosts/desktop-amd.nix` | 7 | `../configuration.nix` | Nix import |
| `hosts/desktop-nvidia.nix` | 7 | `../configuration.nix` | Nix import |
| `hosts/desktop-intel.nix` | 7 | `../configuration.nix` | Nix import |
| `hosts/desktop-vm.nix` | 7 | `../configuration.nix` | Nix import |
| `flake.nix` | ~348 | `./configuration.nix` | Nix import inside `nixosModules.base` |

#### Script reference (will cause preflight soft-fail if not updated):
| File | Line | Reference | Type |
|---|---|---|---|
| `scripts/preflight.sh` | 118-119 | `configuration.nix` | bash `grep` against filename (stateVersion check) |

#### Comment references (no build impact, but should be kept accurate):
| File | Line | Reference | Type |
|---|---|---|---|
| `modules/gnome.nix` | 132 | `configuration.nix` | Code comment (desktop only) |
| `.github/copilot-instructions.md` | 83, 89, 92, 578 | `configuration.nix` | Documentation |

### 1.3 Kora Icon Theme — How It Is Currently Implemented

Kora is applied using **two layers** depending on the role:

#### Desktop / Server / Stateless (home-manager roles):
1. **Package** — `kora-icon-theme` in `home.packages` in the respective `home-<role>.nix`
2. **GTK config** — `gtk.iconTheme = { name = "kora"; package = pkgs.kora-icon-theme; }` in `home-<role>.nix`
3. **dconf (user-level)** — `dconf.settings."org/gnome/desktop/interface".icon-theme = "kora"` in `home-<role>.nix`

#### HTPC (system-level dconf + home-manager dconf):
1. **Package** — `kora-icon-theme` in `environment.systemPackages` in `configuration-htpc.nix`
2. **System dconf** — `programs.dconf.profiles.user.databases[0].settings."org/gnome/desktop/interface".icon-theme = "kora"` in `configuration-htpc.nix`
3. **User dconf** (home-manager) — `dconf.settings."org/gnome/desktop/interface".icon-theme = "kora"` in `home-htpc.nix` (redundant, but matches the system setting and ensures the home db takes precedence)
4. **No `gtk.iconTheme`** — HTPC does not declare `gtk.enable` or `gtk.iconTheme` in `home-htpc.nix`

### 1.4 Bibata-Modern-Classic Cursor — Current State by Role

#### Desktop (`home-desktop.nix`) — **Complete**
- `bibata-cursors` in `home.packages` ✓
- `home.pointerCursor = { name = "Bibata-Modern-Classic"; package = pkgs.bibata-cursors; size = 24; }` ✓
- `gtk.cursorTheme = { name = "Bibata-Modern-Classic"; package = pkgs.bibata-cursors; size = 24; }` ✓
- `dconf.settings."org/gnome/desktop/interface".cursor-theme = "Bibata-Modern-Classic"` ✓
- `dconf.settings."org/gnome/desktop/interface".cursor-size = 24` ✓

#### HTPC (`home-htpc.nix` + `configuration-htpc.nix`) — **Partial / Broken**
- `bibata-cursors` package: **MISSING** — not in `home.packages` (no packages section) and not in `environment.systemPackages` in `configuration-htpc.nix` ✗
- `home.pointerCursor`: **MISSING** ✗
- `gtk.enable` / `gtk.cursorTheme`: **MISSING** ✗
- `dconf.settings."org/gnome/desktop/interface".cursor-theme = "Bibata-Modern-Classic"`: present in `home-htpc.nix` ✓
- `dconf.settings."org/gnome/desktop/interface".cursor-size = 24`: present in `home-htpc.nix` ✓
- System dconf (`programs.dconf.profiles.user.databases`): cursor-theme/cursor-size **not set** in `configuration-htpc.nix` ✗

The dconf keys reference the cursor theme name, but the `bibata-cursors` package is never installed anywhere in the HTPC closure. GNOME will silently fall back to the default cursor.

#### Server (`home-server.nix`) — **Complete**
- `bibata-cursors` in `home.packages` ✓
- `home.pointerCursor` ✓
- `gtk.cursorTheme` ✓
- dconf cursor-theme and cursor-size ✓

#### Stateless (`home-stateless.nix`) — **Complete**
- `bibata-cursors` in `home.packages` ✓
- `home.pointerCursor` ✓
- `gtk.cursorTheme` ✓
- dconf cursor-theme and cursor-size ✓

---

## 2. Problem Definition

### Problem 1: Naming Inconsistency
`configuration.nix` violates the established naming convention. All other roles use `configuration-<role>.nix`. This creates confusion when navigating the repo and breaks the implied pattern used in documentation and copilot instructions.

### Problem 2: HTPC Cursor Not Functional
The HTPC role has cursor-theme dconf keys set in `home-htpc.nix` but the `bibata-cursors` package is never installed anywhere in the HTPC system closure. Without the package:
- GNOME's cursor loader cannot find `Bibata-Modern-Classic` themes
- The system falls back to the default Adwaita cursor
- `home.pointerCursor` is absent so X11 xcursor lookup and `.icons/default/` symlink are never created
- `gtk.cursorTheme` is absent so GTK3/4 config files do not reference the cursor

---

## 3. Proposed Solution Architecture

### 3.1 Rename: `configuration.nix` → `configuration-desktop.nix`

A pure file rename plus surgical path updates in all files that reference the old name. No logic changes to any Nix expressions. The rename aligns with the established `configuration-<role>.nix` pattern.

### 3.2 HTPC Cursor: Match Kora Pattern

Apply cursor configuration to the HTPC role using exactly the same layered approach used for Kora icon theme on HTPC:

1. Add `bibata-cursors` to `environment.systemPackages` in `configuration-htpc.nix` (alongside `kora-icon-theme`)
2. Add `cursor-theme = "Bibata-Modern-Classic"` and `cursor-size = 24` to `programs.dconf.profiles.user.databases` in `configuration-htpc.nix` (alongside `icon-theme = "kora"`)
3. Add `home.pointerCursor` and `gtk.cursorTheme` to `home-htpc.nix` (matching desktop/server/stateless pattern)
4. The dconf user-level keys in `home-htpc.nix` already set cursor-theme and cursor-size — these remain as-is

Desktop, server, and stateless are already fully configured and require no changes for cursor.

---

## 4. Implementation Plan

### Step 1: Rename the file

```
git mv configuration.nix configuration-desktop.nix
```

Or on the host: rename the file at the filesystem level.

### Step 2: Update Nix import paths (hard wiring)

**File: `hosts/desktop-amd.nix`**
```nix
# OLD:
    ../configuration.nix
# NEW:
    ../configuration-desktop.nix
```

**File: `hosts/desktop-nvidia.nix`**
```nix
# OLD:
    ../configuration.nix
# NEW:
    ../configuration-desktop.nix
```

**File: `hosts/desktop-intel.nix`**
```nix
# OLD:
    ../configuration.nix
# NEW:
    ../configuration-desktop.nix
```

**File: `hosts/desktop-vm.nix`**
```nix
# OLD:
    ../configuration.nix
# NEW:
    ../configuration-desktop.nix
```

**File: `flake.nix`** (inside `nixosModules.base`):
```nix
# OLD:
          ./configuration.nix
# NEW:
          ./configuration-desktop.nix
```

### Step 3: Update preflight.sh stateVersion check

**File: `scripts/preflight.sh`** (lines ~118–120):
```bash
# OLD:
echo "[4/9] Verifying system.stateVersion in configuration.nix..."
if grep -q 'system\.stateVersion' configuration.nix; then
  pass "system.stateVersion is present in configuration.nix"
else
  fail "system.stateVersion is missing from configuration.nix"

# NEW:
echo "[4/9] Verifying system.stateVersion in configuration-desktop.nix..."
if grep -q 'system\.stateVersion' configuration-desktop.nix; then
  pass "system.stateVersion is present in configuration-desktop.nix"
else
  fail "system.stateVersion is missing from configuration-desktop.nix"
```

### Step 4: Update comment in `modules/gnome.nix`

**File: `modules/gnome.nix`** (line ~132):
```nix
# OLD:
    # NOTE: gnome-extension-manager is installed in configuration.nix (desktop only).
# NEW:
    # NOTE: gnome-extension-manager is installed in configuration-desktop.nix (desktop only).
```

### Step 5: Update `.github/copilot-instructions.md`

Update all four references to `configuration.nix` that describe the desktop role file:
- Line 83: `flake.nix`, `configuration.nix`, and future module files` → `flake.nix`, `configuration-desktop.nix`, and future module files`
- Line 89: `Host configs live in hosts/ and import configuration.nix` → `import configuration-desktop.nix`
- Line 92: `system.stateVersion in configuration.nix MUST NOT be changed` → `system.stateVersion in configuration-desktop.nix MUST NOT be changed`
- Line 578: `Verification that system.stateVersion is present in configuration.nix` → `configuration-desktop.nix`

### Step 6: Add `bibata-cursors` package to HTPC system packages

**File: `configuration-htpc.nix`** — `environment.systemPackages` block:
```nix
# OLD:
  environment.systemPackages = with pkgs; [
    kora-icon-theme
    ghostty
  ];
# NEW:
  environment.systemPackages = with pkgs; [
    bibata-cursors
    kora-icon-theme
    ghostty
  ];
```

### Step 7: Add cursor-theme and cursor-size to HTPC system dconf profile

**File: `configuration-htpc.nix`** — `programs.dconf.profiles.user.databases` block:
```nix
# OLD:
      settings."org/gnome/desktop/interface" = {
        icon-theme   = "kora";
        clock-format = "12h";
      };
# NEW:
      settings."org/gnome/desktop/interface" = {
        cursor-theme = "Bibata-Modern-Classic";
        cursor-size  = 24;
        icon-theme   = "kora";
        clock-format = "12h";
      };
```

Note: `cursor-size` is an integer in dconf. In NixOS `programs.dconf.profiles.user.databases`, integer values are passed as plain Nix integers (not `lib.gvariant.mkInt32`). Home-manager dconf uses `lib.gvariant.mkUint32` for some types; the system dconf profile uses the Nix value directly and the NixOS module infers the GVariant type automatically.

### Step 8: Add `home.pointerCursor` and `gtk.cursorTheme` to `home-htpc.nix`

**File: `home-htpc.nix`** — add after the `dconf.settings` block (before `home.stateVersion`):
```nix
  # ── Cursor (X11 + Wayland) ─────────────────────────────────────────────────
  # Writes env vars, xcursor, and .icons/default.
  # GTK cursor is handled below to prevent activation-script conflicts.
  home.pointerCursor = {
    name    = "Bibata-Modern-Classic";
    package = pkgs.bibata-cursors;
    size    = 24;
  };

  # ── GTK theming ────────────────────────────────────────────────────────────
  # Both iconTheme and cursorTheme declared together to prevent conflicts
  # between Home Manager's pointer-cursor activation scripts and dconf settings.
  gtk.enable = true;
  gtk.iconTheme = {
    name    = "kora";
    package = pkgs.kora-icon-theme;
  };
  gtk.cursorTheme = {
    name    = "Bibata-Modern-Classic";
    package = pkgs.bibata-cursors;
    size    = 24;
  };
```

Note: `kora-icon-theme` must also be listed in the home-manager packages for `gtk.iconTheme` to work correctly (home-manager needs the package ref). Since `home-htpc.nix` does not have a `home.packages` section, we need to add one, OR we can rely on the system-wide `kora-icon-theme` and `bibata-cursors` packages (added in Steps 6 and 7) combined with `useGlobalPkgs = true` in the flake.nix home-manager module. With `useGlobalPkgs = true`, system packages are available to the home-manager activation scripts, so `gtk.iconTheme.package` and `gtk.cursorTheme.package` referencing `pkgs.*` will resolve correctly from the shared pkgs instance.

---

## 5. Dependencies

| Dependency | Source | Notes |
|---|---|---|
| `bibata-cursors` | `nixpkgs` | Provides `Bibata-Modern-Classic` cursor theme. Already present in nixpkgs stable (25.11). Used by desktop/server/stateless — confirmed working. |
| `kora-icon-theme` | `nixpkgs` | Already in use — no change needed for this dependency. |

No new flake inputs are required. No Context7 lookup needed (internal changes only, no new external libraries).

---

## 6. Files Modified Summary

| File | Change Type | Change |
|---|---|---|
| `configuration.nix` | **Rename** → `configuration-desktop.nix` | File renamed |
| `hosts/desktop-amd.nix` | Edit | Import path: `../configuration.nix` → `../configuration-desktop.nix` |
| `hosts/desktop-nvidia.nix` | Edit | Import path: `../configuration.nix` → `../configuration-desktop.nix` |
| `hosts/desktop-intel.nix` | Edit | Import path: `../configuration.nix` → `../configuration-desktop.nix` |
| `hosts/desktop-vm.nix` | Edit | Import path: `../configuration.nix` → `../configuration-desktop.nix` |
| `flake.nix` | Edit | Import path in `nixosModules.base`: `./configuration.nix` → `./configuration-desktop.nix` |
| `scripts/preflight.sh` | Edit | stateVersion check filename: `configuration.nix` → `configuration-desktop.nix` (3 occurrences) |
| `modules/gnome.nix` | Edit | Comment only: `configuration.nix` → `configuration-desktop.nix` |
| `.github/copilot-instructions.md` | Edit | 4 documentation references updated |
| `configuration-htpc.nix` | Edit | Add `bibata-cursors` to `environment.systemPackages`; add `cursor-theme` + `cursor-size` to system dconf profile |
| `home-htpc.nix` | Edit | Add `home.pointerCursor`, `gtk.enable`, `gtk.iconTheme`, `gtk.cursorTheme` |

---

## 7. Risks and Edge Cases

### Risk 1: `cursor-size` GVariant type in system dconf profile
`cursor-size` in `org/gnome/desktop/interface` is a GVariant `i` (int32). In `programs.dconf.profiles.user.databases`, NixOS infers the GVariant type from the Nix value. A plain Nix integer `24` maps to int32 correctly. The home-manager `dconf.settings` in `home-htpc.nix` passes `cursor-size = 24` as a plain integer (confirmed in the existing home-htpc.nix), so the same pattern applies to the system profile. No `lib.gvariant.mkInt32` wrapper needed.

### Risk 2: `gtk.iconTheme` requires the package reference for home-manager activation
`gtk.iconTheme` in home-manager writes GTK config files and needs the package in the build closure. Since HTPC uses `useGlobalPkgs = true`, `pkgs.kora-icon-theme` and `pkgs.bibata-cursors` resolve from the shared nixpkgs instance. The system-wide packages (added to `environment.systemPackages`) also ensure these themes are present on the host at runtime. This is consistent with how the other roles work.

### Risk 3: `home.pointerCursor` + `gtk.cursorTheme` conflict
On desktop/server/stateless, both are set simultaneously. The desktop home-nix includes a comment: "Both iconTheme and cursorTheme declared together to prevent conflicts between Home Manager's pointer-cursor activation scripts and dconf settings." The same pattern must be followed on HTPC. Both `home.pointerCursor` and `gtk.cursorTheme` must be declared in the same `home-htpc.nix` file.

### Risk 4: Missed reference to `configuration.nix`
The grep search returned the definitive list of all Nix-level imports. The only files with `../configuration.nix` or `./configuration.nix` imports are the four desktop host files and `flake.nix`. All other roles already import their own named configuration file. This is confirmed by the absence of `configuration.nix` references in any htpc/server/stateless host file.

### Risk 5: `preflight.sh` check 4 hardcodes the filename
This is a real break. After the rename, `grep -q 'system\.stateVersion' configuration.nix` will always fail (file not found → grep exits non-zero). The preflight script MUST be updated as part of this change.

### Risk 6: Redundant dconf cursor settings on HTPC
After Step 7, the cursor-theme will be set in both `configuration-htpc.nix` (system dconf profile) and `home-htpc.nix` (user dconf via home-manager). Since the user dconf database takes precedence over system dconf databases (per the profile lookup chain `user-db:user` → `system-db:...`), the home-manager value wins. The system-level setting acts as a sensible default and is consistent with how `icon-theme` is currently handled. This is intentional redundancy, not a conflict.

---

## 8. Out of Scope

- Changes to `configuration-htpc.nix`, `configuration-server.nix`, or `configuration-stateless.nix` beyond cursor additions
- Changes to any GPU module files
- Changes to server or stateless cursor configuration (already complete)
- Changes to desktop cursor configuration (already complete)
- Updating `flake.lock`
- Modifying `system.stateVersion`
