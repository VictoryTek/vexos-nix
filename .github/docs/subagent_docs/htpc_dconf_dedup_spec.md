# HTPC dconf Triple-Write Deduplication — Specification

**Audit Finding:** B7 — HTPC dconf triple-write  
**Date:** 2026-04-27  
**Scope:** Eliminate provable dconf key duplication across three HTPC files  

---

## 1. Current State Analysis

### 1.1 Home-Manager Always Active for HTPC

Confirmed via `flake.nix`: the `roles.htpc` entry defines `homeFile = ./home-htpc.nix`, and
`mkHost` unconditionally includes `mkHomeManagerModule r.homeFile` for every role.
Home-manager is **always** active for HTPC — the comment in `configuration-htpc.nix`
("no home-manager on HTPC") is factually wrong and likely the root cause of the
duplicate dconf block being added there.

### 1.2 Sources of dconf Settings for the HTPC Role

| Layer | File | Mechanism |
|-------|------|-----------|
| System dconf (universal base) | `modules/gnome.nix` | `programs.dconf.profiles.user.databases` |
| System dconf (HTPC role addition) | `modules/gnome-htpc.nix` | `programs.dconf.profiles.user.databases` |
| System dconf (HTPC configuration) | `configuration-htpc.nix` | `programs.dconf.profiles.user.databases` |
| Home-manager dconf (universal base) | `home/gnome-common.nix` | `dconf.settings` |
| Home-manager dconf (HTPC role) | `home-htpc.nix` | `dconf.settings` |

Three of these five (gnome-htpc.nix, configuration-htpc.nix, home-htpc.nix) contain
overlapping HTPC-specific keys.

### 1.3 Complete Key Catalogue

#### HTPC-specific keys appearing in 2+ of the 3 target files

| # | dconf Key Path | gnome-htpc.nix | configuration-htpc.nix | home-htpc.nix | Identical? | Authoritative Source |
|---|---------------|---------------|----------------------|--------------|-----------|---------------------|
| 1 | `org/gnome/desktop/interface.accent-color` | `"orange"` | `"orange"` | `"orange"` | **Yes** (triple) | gnome-htpc.nix |
| 2 | `org/gnome/shell.enabled-extensions` | 10 extensions (via `commonExtensions`) | 10 extensions (hardcoded, identical) | 10 extensions (hardcoded, identical) | **Yes** (triple) | gnome-htpc.nix |
| 3 | `org/gnome/shell.favorite-apps` | 8 apps | **7 apps** (DRIFTED — missing `system-update.desktop`, reordered Nautilus/ghostty/up) | 8 apps (identical to gnome-htpc.nix) | **No** — configuration-htpc.nix has drifted | gnome-htpc.nix |

#### Keys in configuration-htpc.nix that duplicate the universal base (gnome.nix)

| # | dconf Key Path | configuration-htpc.nix | gnome.nix (universal) | gnome-common.nix (home universal) | Identical? |
|---|---------------|----------------------|----------------------|----------------------------------|-----------|
| 4 | `org/gnome/desktop/interface.color-scheme` | `"prefer-dark"` | `"prefer-dark"` | `"prefer-dark"` | **Yes** (triple with universal) |
| 5 | `org/gnome/desktop/interface.cursor-theme` | `"Bibata-Modern-Classic"` | `"Bibata-Modern-Classic"` | `"Bibata-Modern-Classic"` | **Yes** |
| 6 | `org/gnome/desktop/interface.icon-theme` | `"kora"` | `"kora"` | `"kora"` | **Yes** |
| 7 | `org/gnome/desktop/interface.clock-format` | `"12h"` | `"12h"` | `"12h"` | **Yes** |

#### Key in configuration-htpc.nix with no other system-level source

| # | dconf Key Path | configuration-htpc.nix | Covered elsewhere? |
|---|---------------|----------------------|-------------------|
| 8 | `org/gnome/desktop/interface.cursor-size` | `lib.gvariant.mkInt32 24` | `home/gnome-common.nix` sets `home.pointerCursor.size = 24` (writes XCURSOR_SIZE + GTK config, not dconf directly). GNOME's built-in default is 24 — no dconf entry needed to get the correct value. |

#### Keys in home-htpc.nix that duplicate gnome-common.nix (imported via `imports`)

| # | dconf Key Path | home-htpc.nix | gnome-common.nix | Identical? |
|---|---------------|--------------|-----------------|-----------|
| 9 | `org/gnome/desktop/interface.color-scheme` | `"prefer-dark"` | `"prefer-dark"` | **Yes** |

#### Keys ONLY in home-htpc.nix (unique — must be KEPT)

| # | dconf Key Path | Value | Why unique |
|---|---------------|-------|-----------|
| 10 | `org/gnome/settings-daemon/plugins/power.sleep-inactive-ac-type` | `"nothing"` | HTPC power policy |
| 11 | `org/gnome/settings-daemon/plugins/power.sleep-inactive-battery-type` | `"nothing"` | HTPC power policy |
| 12 | `org/gnome/desktop/app-folders.folder-children` | `["Office" "Utilities" "System"]` | HTPC app-grid layout |
| 13 | `org/gnome/desktop/app-folders/folders/Office` | name + apps | HTPC app-grid folder |
| 14 | `org/gnome/desktop/app-folders/folders/Utilities` | name + apps | HTPC app-grid folder |
| 15 | `org/gnome/desktop/app-folders/folders/System` | name + apps | HTPC app-grid folder |

### 1.4 favorite-apps Drift Detail

The triple-write has already caused value drift in `favorite-apps`:

**gnome-htpc.nix** (8 items — authoritative):
```
brave-browser.desktop
app.zen_browser.zen.desktop
plex-desktop.desktop
io.freetubeapp.FreeTube.desktop
org.gnome.Nautilus.desktop
io.github.up.desktop
com.mitchellh.ghostty.desktop
system-update.desktop
```

**configuration-htpc.nix** (7 items — DRIFTED):
```
brave-browser.desktop
app.zen_browser.zen.desktop
plex-desktop.desktop
io.freetubeapp.FreeTube.desktop
com.mitchellh.ghostty.desktop     ← reordered
org.gnome.Nautilus.desktop        ← reordered
io.github.up.desktop
                                  ← system-update.desktop MISSING
```

**home-htpc.nix** (8 items — matches gnome-htpc.nix):
```
brave-browser.desktop
app.zen_browser.zen.desktop
plex-desktop.desktop
io.freetubeapp.FreeTube.desktop
org.gnome.Nautilus.desktop
io.github.up.desktop
com.mitchellh.ghostty.desktop
system-update.desktop
```

This drift is the textbook consequence of maintaining the same data in three places.

---

## 2. Problem Definition

**Audit finding B7:** The same dconf settings (enabled-extensions, favorite-apps,
accent-color, color-scheme, etc.) are written in THREE places for the HTPC role:

1. `modules/gnome-htpc.nix` — system dconf (role-specific addition, per Option B)
2. `configuration-htpc.nix` — system dconf (inline block, duplicating gnome-htpc.nix + gnome.nix)
3. `home-htpc.nix` — home-manager dconf (duplicating gnome-htpc.nix + gnome-common.nix)

**Quantification:**
- **9 dconf keys** duplicated across 2–3 files (keys #1–9 in the catalogue above)
- **~65 lines** of redundant configuration
- **1 confirmed drift** (`favorite-apps` in configuration-htpc.nix lost `system-update.desktop`)
- **1 factually incorrect comment** ("no home-manager on HTPC") that caused the
  configuration-htpc.nix dconf block to be written in the first place

---

## 3. Proposed Solution Architecture

### 3.1 Authority Model

Per Option B (Common base + role additions):

| Authority | File | Scope |
|-----------|------|-------|
| Universal system defaults | `modules/gnome.nix` | cursor-theme, icon-theme, clock-format, color-scheme, wallpaper, screensaver, button-layout, logo, housekeeping |
| HTPC system defaults | `modules/gnome-htpc.nix` | accent-color, enabled-extensions, favorite-apps |
| Universal home-manager settings | `home/gnome-common.nix` | Same as gnome.nix (user-level mirror) + idle-delay, lock-delay |
| HTPC home-manager overrides | `home-htpc.nix` | **Only unique user-level keys:** power policy, app-folders |

### 3.2 What to Remove from `configuration-htpc.nix`

Remove the **entire** `programs.dconf.profiles.user.databases` block (approximately
lines 60–96). Every key in it is either:

- A duplicate of `modules/gnome.nix` universal base (cursor-theme, icon-theme,
  clock-format, color-scheme)
- A duplicate of `modules/gnome-htpc.nix` role addition (accent-color,
  enabled-extensions, favorite-apps)
- Redundant with GNOME's built-in default (cursor-size = 24)

Also remove the misleading comment `# Enable GNOME Shell extensions at the system
level (no home-manager on HTPC).` — home-manager is always active.

Additionally, remove `bibata-cursors` and `kora-icon-theme` from
`configuration-htpc.nix`'s `environment.systemPackages` — they are already declared
in `modules/gnome.nix`'s `environment.systemPackages` (NixOS deduplicates, but the
declaration is confusing and tied to the removed dconf block). Retain `ghostty` and
`unstable.plex-desktop` which are genuinely HTPC-specific packages. Update the
comment above `environment.systemPackages` to reflect the remaining packages.

### 3.3 What to Remove from `home-htpc.nix`

Remove these dconf.settings entries (all redundant):

| Key | Why redundant |
|-----|--------------|
| `org/gnome/shell.enabled-extensions` | Identical to `gnome-htpc.nix` system default |
| `org/gnome/shell.favorite-apps` | Identical to `gnome-htpc.nix` system default |
| `org/gnome/desktop/interface.color-scheme` | Already set by `gnome-common.nix` (imported) |
| `org/gnome/desktop/interface.accent-color` | Identical to `gnome-htpc.nix` system default |

Remove the entire `"org/gnome/shell"` block and the entire
`"org/gnome/desktop/interface"` block from `dconf.settings`.

### 3.4 What to Keep in `home-htpc.nix`

These dconf.settings entries are **unique** and must be retained:

- `"org/gnome/settings-daemon/plugins/power"` — HTPC sleep policy
- `"org/gnome/desktop/app-folders"` — folder-children
- `"org/gnome/desktop/app-folders/folders/Office"` — folder definition
- `"org/gnome/desktop/app-folders/folders/Utilities"` — folder definition
- `"org/gnome/desktop/app-folders/folders/System"` — folder definition

### 3.5 What to Move Between Files

**No key moves required.** All unique keys are already in their correct file per
Option B. The `cursor-size` key in configuration-htpc.nix is simply removed (not
moved) because GNOME's built-in default of 24 matches the desired value.

---

## 4. Implementation Steps

### Step 1: Edit `configuration-htpc.nix`

**Remove** the entire `programs.dconf.profiles.user.databases` block, including:
- The `settings."org/gnome/desktop/interface"` sub-block (cursor-theme, cursor-size,
  icon-theme, clock-format, color-scheme, accent-color)
- The `settings."org/gnome/shell"` sub-block (enabled-extensions, favorite-apps)
- The surrounding comment about "no home-manager on HTPC"

**Remove** `bibata-cursors` and `kora-icon-theme` from `environment.systemPackages`.

**Update** the `# ---------- Icons ----------` comment block to reflect the remaining
packages (ghostty, plex-desktop). Example replacement:

```nix
  # ---------- HTPC-specific packages ----------
  environment.systemPackages = with pkgs; [
    ghostty
    unstable.plex-desktop  # Plex media client (nixpkgs-unstable)
  ];
```

**Lines removed:** ~40 (the dconf block + 2 duplicate package lines + comments)

### Step 2: Edit `home-htpc.nix`

**Remove** the `"org/gnome/shell"` block from `dconf.settings` (enabled-extensions
and favorite-apps — both identical to gnome-htpc.nix system defaults).

**Remove** the `"org/gnome/desktop/interface"` block from `dconf.settings`
(color-scheme duplicates gnome-common.nix; accent-color duplicates gnome-htpc.nix).

**Keep** all remaining `dconf.settings` entries:
- `"org/gnome/settings-daemon/plugins/power"`
- `"org/gnome/desktop/app-folders"`
- `"org/gnome/desktop/app-folders/folders/Office"`
- `"org/gnome/desktop/app-folders/folders/Utilities"`
- `"org/gnome/desktop/app-folders/folders/System"`

**Lines removed:** ~25 (the shell block + interface block)

### Step 3: No changes to `modules/gnome-htpc.nix`

This file is already the authoritative source for HTPC-specific system dconf keys.
No modifications needed.

### Step 4: No changes to `modules/gnome.nix` or `home/gnome-common.nix`

These universal bases are not affected by HTPC dedup.

---

## 5. Semantic-Equivalence Checklist

For each dconf key set for the HTPC role, confirm the effective user-visible value
is unchanged after dedup:

| # | dconf Key | Before (effective source) | After (effective source) | Value unchanged? |
|---|-----------|--------------------------|-------------------------|-----------------|
| 1 | `accent-color` | home-htpc.nix user-db (`"orange"`) | gnome-htpc.nix system-db (`"orange"`) | **Yes** — same value |
| 2 | `enabled-extensions` | home-htpc.nix user-db (10 exts) | gnome-htpc.nix system-db (10 exts) | **Yes** — identical lists |
| 3 | `favorite-apps` | home-htpc.nix user-db (8 apps) | gnome-htpc.nix system-db (8 apps) | **Yes** — identical lists |
| 4 | `color-scheme` | home-htpc.nix user-db (`"prefer-dark"`) via gnome-common.nix | gnome-common.nix user-db (`"prefer-dark"`) | **Yes** — gnome-common.nix still sets it |
| 5 | `cursor-theme` | gnome.nix system-db (`"Bibata-Modern-Classic"`) + gnome-common.nix user-db | gnome.nix system-db + gnome-common.nix user-db (unchanged) | **Yes** — only configuration-htpc.nix duplicate removed |
| 6 | `icon-theme` | gnome.nix system-db (`"kora"`) + gnome-common.nix user-db | gnome.nix system-db + gnome-common.nix user-db (unchanged) | **Yes** |
| 7 | `clock-format` | gnome.nix system-db (`"12h"`) + gnome-common.nix user-db | gnome.nix system-db + gnome-common.nix user-db (unchanged) | **Yes** |
| 8 | `cursor-size` | configuration-htpc.nix system-db (`24`) | GNOME built-in default (`24`) + pointerCursor.size = 24 | **Yes** — 24 is GNOME's default; cursor rendering handled by home.pointerCursor |
| 9 | Power settings | home-htpc.nix user-db (KEPT) | home-htpc.nix user-db (unchanged) | **Yes** |
| 10–15 | App folders | home-htpc.nix user-db (KEPT) | home-htpc.nix user-db (unchanged) | **Yes** |

**All effective values are preserved.**

---

## 6. Dependencies

None. This is a pure Nix configuration refactor with no new packages, inputs, or
external dependencies.

---

## 7. Risks and Mitigations

### Risk 1: Stale user dconf keys after removing from home-manager

**Description:** Home-manager's dconf module uses `dconf load` which only writes keys
present in the configuration — it never deletes keys. After removing
enabled-extensions, favorite-apps, accent-color, and color-scheme from
home-htpc.nix, the previously-written values persist in the user dconf database
(`~/.config/dconf/user`). These stale user-db values override system defaults.

**Impact:** Immediately: none (stale values match system defaults). Long-term: if
gnome-htpc.nix's favorite-apps or enabled-extensions are changed in a future commit,
the stale user-db values would take precedence until manually reset.

**Mitigation:** After the first `home-manager switch` (or `nixos-rebuild switch`)
with the new configuration, run:
```bash
dconf reset /org/gnome/shell/favorite-apps
dconf reset /org/gnome/shell/enabled-extensions
dconf reset /org/gnome/desktop/interface/accent-color
```
This clears the stale user-db entries, allowing system defaults to show through.
Document this as a one-time post-deployment step.

### Risk 2: List-type key merge semantics

**Description:** `programs.dconf.profiles.user.databases` is a list type in NixOS.
Multiple modules (gnome.nix, gnome-htpc.nix) each append database entries. For
non-overlapping keys this is safe. For overlapping keys (e.g., if gnome.nix and
gnome-htpc.nix both set `org/gnome/desktop/interface`), the last database in the
merged list may override earlier ones depending on NixOS dconf module ordering.

**Impact:** Currently safe — gnome-htpc.nix only sets `accent-color` in
`org/gnome/desktop/interface`, while gnome.nix sets `cursor-theme`, `icon-theme`,
`clock-format`, `color-scheme`. These are different keys within the same path, and
NixOS writes them to separate database files with defined precedence.

**Mitigation:** No action needed for this change. If future changes add overlapping
keys to multiple database entries, consolidation will be required.

### Risk 3: False positive in overlap analysis

**Description:** Risk of identifying a key as redundant when it is actually the
only source setting that value.

**Impact:** Removing it would unset the key, reverting to GNOME defaults.

**Mitigation:** The catalogue in §1.3 explicitly tracks every key across all 5
source files. Each removal is backed by a surviving source. The semantic-equivalence
checklist in §5 validates every key has an unchanged effective value.

---

## 8. Out of Scope

### Desktop role double-write (noted, not addressed)

`home-desktop.nix` sets `enabled-extensions` and `favorite-apps` in `dconf.settings`
that are identical to `modules/gnome-desktop.nix`'s system dconf. This is a
**double-write** (system + home-manager), not a triple-write — `configuration-desktop.nix`
has no dconf block. Fixing this is a separate task with the same pattern as this spec.

### Server / stateless role dconf

Not analyzed. Out of scope for this change.

### Package deduplication beyond the dconf-tied entries

`configuration-htpc.nix` duplicates `bibata-cursors` and `kora-icon-theme` from
`modules/gnome.nix`. Removal of these two is included in this spec because they are
directly tied to the removed dconf block and its misleading comment. Broader package
dedup across other files is out of scope.

### GNOME module structure changes

No module renames, splits, or architectural changes beyond dconf key removal.

### Flatpak, systemd, or package list changes

No modifications to Flatpak services, systemd units, or package lists (beyond the
two duplicate icon/cursor packages noted above).

---

## 9. Validation Plan

### 9.1 Build Validation

```bash
# Flake structure check
nix flake check

# Dry-build HTPC outputs (the directly affected role)
sudo nixos-rebuild dry-build --flake .#vexos-htpc-amd
sudo nixos-rebuild dry-build --flake .#vexos-htpc-nvidia
sudo nixos-rebuild dry-build --flake .#vexos-htpc-vm

# Verify other roles are unaffected
sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd
sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia
sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm
```

### 9.2 Semantic Verification

After building, verify the effective dconf database for an HTPC output still
contains the expected keys:

```bash
# Evaluate the dconf profile databases for htpc-amd
nix eval .#nixosConfigurations.vexos-htpc-amd.config.programs.dconf.profiles.user.databases --json | python3 -m json.tool
```

Confirm:
- `accent-color = "orange"` appears exactly once (from gnome-htpc.nix)
- `enabled-extensions` appears exactly once (from gnome-htpc.nix)
- `favorite-apps` with 8 entries appears exactly once (from gnome-htpc.nix)
- `cursor-theme`, `icon-theme`, `clock-format`, `color-scheme` each appear exactly
  once (from gnome.nix)
- No duplicate keys across database entries

### 9.3 Invariant Checks

- `system.stateVersion` unchanged in `configuration-htpc.nix`
- `hardware-configuration.nix` not committed to repository
- No new flake inputs added
- `home.stateVersion` unchanged in `home-htpc.nix`

### 9.4 Post-Deployment (manual, after live switch)

```bash
# One-time: clear stale user-db keys written by previous home-manager activation
dconf reset /org/gnome/shell/favorite-apps
dconf reset /org/gnome/shell/enabled-extensions
dconf reset /org/gnome/desktop/interface/accent-color
```

Then verify user-visible GNOME state matches expectations (correct accent color,
dock favorites, shell extensions loaded).
