# Specification: Server Branding + Global dconf Settings

**Feature Name:** `server_branding_dconf_globals`
**Date:** 2026-04-17
**Status:** Draft

---

## 1. Current State Analysis

### 1.1 Repository Structure (relevant files)

| File | Purpose |
|------|---------|
| `configuration-desktop.nix` | Desktop role system config; sets `vexos.branding.role = "desktop"` |
| `configuration-server.nix` | Server role system config; sets `vexos.branding.role = "server"` |
| `configuration-htpc.nix` | HTPC role; sets `vexos.branding.role = "htpc"` |
| `configuration-stateless.nix` | Stateless role; sets `vexos.branding.role = "stateless"` |
| `modules/branding.nix` | Deploys Plymouth logo, pixmaps, GDM logo, OS identity — driven by `vexos.branding.role` |
| `modules/gnome.nix` | Installs GNOME stack + extensions for ALL roles via `environment.systemPackages` |
| `home-desktop.nix` | Home Manager for desktop: packages, shell, GTK theme, cursor, dconf |
| `home-server.nix` | Home Manager for server: packages, shell, GTK theme, cursor, dconf |
| `home-htpc.nix` | Home Manager for HTPC: shell, GTK theme, cursor, dconf (minimal packages) |
| `home-stateless.nix` | Home Manager for stateless: mirrors desktop minus gaming |
| `home/photogimp.nix` | Example of existing Home Manager sub-module pattern |

### 1.2 Branding Asset Inventory

All four roles have complete branding asset directories:

**`files/pixmaps/<role>/`** — same fileset for all four roles:
- `vex.png`, `system-logo-white.png`
- `fedora-gdm-logo.png`, `fedora-logo-small.png`, `fedora-logo-sprite.{png,svg}`
- `fedora-logo.png`, `fedora_logo_med.png`, `fedora_whitelogo_med.png`

**`files/background_logos/<role>/`** — same fileset for all four roles:
- `fedora_lightbackground.svg`, `fedora_darkbackground.svg`

**`files/plymouth/<role>/`** — same fileset for all four roles:
- `watermark.png`

**`wallpapers/<role>/`** — same fileset for all four roles:
- `vex-bb-light.jxl`, `vex-bb-dark.jxl`

### 1.3 Server Branding — Current Status

**Result: Server branding IS already fully wired.**

Verification:

| Branding Component | Status | Evidence |
|--------------------|--------|---------|
| `vexos.branding.role = "server"` | ✓ Present | `configuration-server.nix` line 21 |
| `system.nixos.distroName = "VexOS Server"` | ✓ Present | `configuration-server.nix` via `lib.mkOverride 500` |
| Plymouth logo | ✓ Wired | `modules/branding.nix` uses `files/plymouth/server/watermark.png` |
| GDM logo | ✓ Wired | `modules/branding.nix` deploys `files/pixmaps/server/fedora-gdm-logo.png` |
| System pixmaps | ✓ Wired | `modules/branding.nix` copies all `files/pixmaps/server/` assets |
| Background logo SVGs | ✓ Wired | `modules/branding.nix` copies `files/background_logos/server/` → `/run/current-system/sw/share/pixmaps/vex-background-logo*.svg` |
| Wallpaper files | ✓ Wired | `home-server.nix` copies `wallpapers/server/vex-bb-{light,dark}.jxl` → `~/Pictures/Wallpapers/` |
| dconf wallpaper URI | ✓ Wired | `home-server.nix` sets `picture-uri`/`picture-uri-dark` pointing to the deployed wallpapers |
| background-logo extension dconf | ✓ Wired | `home-server.nix` points logo-file to `/run/current-system/sw/share/pixmaps/vex-background-logo.svg` |

**Conclusion for server branding:** No wiring changes are needed. The asset pipeline from `files/` → branding module → GNOME session is complete and correct for the server role.

### 1.4 dconf Settings Inventory — All Roles

The table below lists every dconf key in use and which home file currently declares it.

| dconf Path | Key | Desktop | Server | HTPC | Stateless |
|-----------|-----|---------|--------|------|-----------|
| `org/gnome/shell` | `enabled-extensions` | ✓ (13, incl. gamemode) | ✓ (11, no gamemode) | **✗ MISSING** | ✓ (11, no gamemode) |
| `org/gnome/shell` | `favorite-apps` | ✓ (role-specific) | ✓ (role-specific) | ✓ (role-specific) | ✓ (role-specific) |
| `org/gnome/desktop/interface` | `clock-format` | ✓ `"12h"` | ✓ `"12h"` | ✓ `"12h"` | ✓ `"12h"` |
| `org/gnome/desktop/interface` | `cursor-size` | ✓ `24` | ✓ `24` | ✓ `24` | ✓ `24` |
| `org/gnome/desktop/interface` | `cursor-theme` | ✓ `"Bibata-Modern-Classic"` | ✓ | ✓ | ✓ |
| `org/gnome/desktop/interface` | `icon-theme` | ✓ `"kora"` | ✓ | ✓ | ✓ |
| `org/gnome/desktop/wm/preferences` | `button-layout` | ✓ | ✓ | ✓ | ✓ |
| `org/gnome/desktop/background` | `picture-uri` | ✓ (role-specific path) | ✓ | ✓ | ✓ |
| `org/gnome/desktop/background` | `picture-uri-dark` | ✓ (role-specific path) | ✓ | ✓ | ✓ |
| `org/gnome/desktop/background` | `picture-options` | ✓ `"zoom"` | ✓ | ✓ | ✓ |
| `org/gnome/shell/extensions/dash-to-dock` | `dock-position` | ✓ `"LEFT"` | ✓ | ✓ | ✓ |
| `org/fedorahosted/background-logo-extension` | `logo-file` | ✓ | ✓ | ✓ | ✓ |
| `org/fedorahosted/background-logo-extension` | `logo-file-dark` | ✓ | ✓ | ✓ | ✓ |
| `org/fedorahosted/background-logo-extension` | `logo-always-visible` | ✓ | ✓ | ✓ | ✓ |
| `org/gnome/desktop/screensaver` | `lock-enabled` | ✓ `false` | ✓ | ✓ | ✓ |
| `org/gnome/desktop/screensaver` | `lock-delay` | ✓ `mkUint32 0` | ✓ | ✓ | ✓ |
| `org/gnome/session` | `idle-delay` | ✓ `mkUint32 300` | ✓ | ✓ | ✓ |
| `org/gnome/settings-daemon/plugins/power` | `sleep-inactive-ac-type` | ✗ | ✗ | ✓ (HTPC-only) | ✗ |
| `org/gnome/settings-daemon/plugins/power` | `sleep-inactive-battery-type` | ✗ | ✗ | ✓ (HTPC-only) | ✗ |
| `org/gnome/desktop/app-folders` | `folder-children` | ✓ (role-specific) | ✓ (role-specific) | ✓ (role-specific) | ✓ (role-specific) |

### 1.5 GTK / Cursor Theme Settings Inventory

| Setting | Desktop | Server | HTPC | Stateless |
|---------|---------|--------|------|-----------|
| `home.pointerCursor` (Bibata-Modern-Classic, size 24) | ✓ | ✓ | ✓ | ✓ |
| `gtk.enable = true` | ✓ | ✓ | ✓ | ✓ |
| `gtk.iconTheme` (kora) | ✓ | ✓ | ✓ | ✓ |
| `gtk.cursorTheme` (Bibata-Modern-Classic) | ✓ | ✓ | ✓ | ✓ |
| `bibata-cursors` in `home.packages` | ✓ | ✓ | ✗ (auto via gtk/cursor decl) | ✓ |
| `kora-icon-theme` in `home.packages` | ✓ | ✓ | ✗ (auto via gtk/cursor decl) | ✓ |

Note: HTPC doesn't declare `bibata-cursors` or `kora-icon-theme` in `home.packages`; Home Manager auto-installs them via their use in `gtk.iconTheme.package` and `home.pointerCursor.package`. This works but is inconsistent with other roles.

---

## 2. Problem Definition

### 2.1 Critical Bugs

**BUG-1: HTPC is missing `enabled-extensions`**

`home-htpc.nix` declares only `favorite-apps` under `org/gnome/shell`. The `enabled-extensions` key is entirely absent. All 11 GNOME Shell extensions installed by `modules/gnome.nix` (appindicator, dash-to-dock, alphabetical-app-grid, etc.) are installed on disk but will **not be activated** on the HTPC GNOME session.

This is a functional regression — the GNOME shell on HTPC has no active extensions even though they are installed.

### 2.2 Architecture Debt

**DEBT-1: Massive dconf duplication across four home files**

The following dconf groups are **byte-for-byte identical** across all four home files:
- `org/gnome/desktop/interface` (all 4 keys)
- `org/gnome/desktop/wm/preferences` (`button-layout`)
- `org/gnome/desktop/background` (`picture-options` only; URIs differ per role)
- `org/gnome/shell/extensions/dash-to-dock` (`dock-position`)
- `org/fedorahosted/background-logo-extension` (all 3 keys)
- `org/gnome/desktop/screensaver` (both keys)
- `org/gnome/session` (`idle-delay`)

**DEBT-2: GTK/cursor theme declarations duplicated across four home files**

`home.pointerCursor`, `gtk.enable`, `gtk.iconTheme`, and `gtk.cursorTheme` are identical in all four home files. Any theme change currently requires editing 4 files.

### 2.3 Non-Issues (Confirmed Working)

- Server branding is complete and correct — no changes needed to `configuration-server.nix` or `modules/branding.nix`.
- Wallpaper files are already role-specific in each home file.
- The background-logo extension dconf keys already point to `/run/current-system/sw/share/pixmaps/vex-background-logo*.svg`, which is populated by `modules/branding.nix` using the role-specific `files/background_logos/<role>/` assets.

---

## 3. Proposed Solution Architecture

### 3.1 Approach: Shared Home Manager Module

Create a new file `home/gnome-common.nix` — a Home Manager sub-module following the same pattern as the existing `home/photogimp.nix`. This module captures all settings that are identical across ALL roles.

Each role's home file (`home-desktop.nix`, `home-server.nix`, `home-htpc.nix`, `home-stateless.nix`) imports `./home/gnome-common.nix` and removes its now-redundant blocks.

**Why a Home Manager module (not a NixOS system-level module)?**

- GTK theming (`gtk.*`) and cursor settings (`home.pointerCursor`) are Home Manager concepts — they belong in user-space configuration.
- dconf settings are user-level state, managed through Home Manager's activation scripts.
- Putting them in a NixOS system module would require `programs.dconf.profiles.user.databases` (system-level dconf locks), which is heavy-handed for user preferences.
- The existing `home/photogimp.nix` demonstrates this is the established project pattern.

### 3.2 Decision: What Goes in the Shared Module vs. Stays Per-Role

**Shared (`home/gnome-common.nix`):**

| Category | Keys |
|----------|------|
| Packages | `bibata-cursors`, `kora-icon-theme` |
| Cursor | `home.pointerCursor` (Bibata-Modern-Classic, size 24) |
| GTK | `gtk.enable`, `gtk.iconTheme` (kora), `gtk.cursorTheme` (Bibata-Modern-Classic) |
| dconf `org/gnome/desktop/interface` | `clock-format = "12h"`, `cursor-size = 24`, `cursor-theme`, `icon-theme` |
| dconf `org/gnome/desktop/wm/preferences` | `button-layout` |
| dconf `org/gnome/desktop/background` | `picture-options = "zoom"` only |
| dconf `org/gnome/shell/extensions/dash-to-dock` | `dock-position = "LEFT"` |
| dconf `org/fedorahosted/background-logo-extension` | `logo-file`, `logo-file-dark`, `logo-always-visible` |
| dconf `org/gnome/desktop/screensaver` | `lock-enabled = false`, `lock-delay = mkUint32 0` |
| dconf `org/gnome/session` | `idle-delay = mkUint32 300` |

**Stays Per-Role (NOT in common module):**

| Category | Reason |
|----------|--------|
| `org/gnome/shell.enabled-extensions` | Desktop includes gamemode; others do not. Full list must be specified explicitly per role. |
| `org/gnome/shell.favorite-apps` | Completely role-specific |
| `org/gnome/desktop/background.picture-uri` / `picture-uri-dark` | Different wallpaper paths per role |
| `org/gnome/desktop/app-folders.*` | Desktop has Games/Game Utilities; HTPC has media apps; others differ |
| `org/gnome/settings-daemon/plugins/power.*` | HTPC-only: `sleep-inactive-*-type = "nothing"` |

### 3.3 dconf Module Merge Safety

Home Manager merges `dconf.settings` from all imported modules using the Nix module system's `lib.mkMerge`. When two modules set keys under the **same dconf schema path**, the keys are merged (each module contributes different attribute names). When two modules both set the **same key** under the same schema path, there is a conflict.

Since `home/gnome-common.nix` will set `picture-options` and each role home will set `picture-uri`/`picture-uri-dark` (different keys under `org/gnome/desktop/background`), this merge is safe — no conflicts.

Care must be taken to ensure no key is set in BOTH the common module AND a role-specific home file after the refactor.

---

## 4. Implementation Steps

### Step 1: Create `home/gnome-common.nix`

**File:** `home/gnome-common.nix`
**Action:** Create new file

```nix
# home/gnome-common.nix
# Shared GNOME theming, cursor/icon settings, and common dconf keys
# applied to ALL roles (desktop, server, htpc, stateless).
# Import this from each role's home file.
{ pkgs, lib, ... }:
{
  # ── Theme packages ─────────────────────────────────────────────────────────
  # Required for gtk.iconTheme and home.pointerCursor declarations below.
  home.packages = with pkgs; [
    bibata-cursors
    kora-icon-theme
  ];

  # ── Cursor (X11 + Wayland) ─────────────────────────────────────────────────
  home.pointerCursor = {
    name    = "Bibata-Modern-Classic";
    package = pkgs.bibata-cursors;
    size    = 24;
  };

  # ── GTK theming ────────────────────────────────────────────────────────────
  # Writes gtk-3/4 config files for non-GNOME apps.
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

  # ── Common GNOME dconf settings ────────────────────────────────────────────
  # These keys are identical across all roles. Role-specific keys (wallpaper
  # URIs, enabled-extensions, favorite-apps, app-folders) remain in each
  # role's home file.
  dconf.settings = {

    "org/gnome/desktop/interface" = {
      clock-format = "12h";
      cursor-size  = 24;
      cursor-theme = "Bibata-Modern-Classic";
      icon-theme   = "kora";
    };

    "org/gnome/desktop/wm/preferences" = {
      button-layout = "appmenu:minimize,maximize,close";
    };

    # picture-options is the same on every role; URIs are role-specific and
    # declared in each home file under the same schema path (merges safely).
    "org/gnome/desktop/background" = {
      picture-options = "zoom";
    };

    "org/gnome/shell/extensions/dash-to-dock" = {
      dock-position = "LEFT";
    };

    "org/fedorahosted/background-logo-extension" = {
      logo-file         = "/run/current-system/sw/share/pixmaps/vex-background-logo.svg";
      logo-file-dark    = "/run/current-system/sw/share/pixmaps/vex-background-logo-dark.svg";
      logo-always-visible = true;
    };

    "org/gnome/desktop/screensaver" = {
      lock-enabled = false;
      lock-delay   = lib.gvariant.mkUint32 0;
    };

    "org/gnome/session" = {
      idle-delay = lib.gvariant.mkUint32 300;
    };

  };
}
```

---

### Step 2: Update `home-desktop.nix`

**Action:** Add import, remove now-shared declarations, keep role-specific content.

Changes:
1. Add `./home/gnome-common.nix` to the `imports` list.
2. Remove from `home.packages`: `bibata-cursors`, `kora-icon-theme` (still keep all other packages).
3. Remove entire `home.pointerCursor` block.
4. Remove `gtk.enable`, `gtk.iconTheme`, `gtk.cursorTheme` blocks.
5. In `dconf.settings`, remove the following sub-sections entirely:
   - `"org/gnome/desktop/interface"` (all 4 keys)
   - `"org/gnome/desktop/wm/preferences"` (entire block)
   - `picture-options` line from `"org/gnome/desktop/background"` (keep `picture-uri` and `picture-uri-dark`)
   - `"org/gnome/shell/extensions/dash-to-dock"` (entire block)
   - `"org/fedorahosted/background-logo-extension"` (entire block)
   - `"org/gnome/desktop/screensaver"` (entire block)
   - `"org/gnome/session"` (entire block)
6. Keep all of:
   - `org/gnome/shell.enabled-extensions` (with gamemode extension)
   - `org/gnome/shell.favorite-apps`
   - `org/gnome/desktop/background.picture-uri` and `picture-uri-dark`
   - All `org/gnome/desktop/app-folders` blocks (all 7 of them)

---

### Step 3: Update `home-server.nix`

**Action:** Add import, remove now-shared declarations, keep role-specific content.

Changes:
1. Add `imports = [ ./home/gnome-common.nix ];` (new top-level imports block).
2. Remove from `home.packages`: `bibata-cursors`, `kora-icon-theme` (keep ghostty, tree, ripgrep, fd, bat, eza, fzf, wl-clipboard, fastfetch, blivet-gui).
3. Remove entire `home.pointerCursor` block.
4. Remove `gtk.enable`, `gtk.iconTheme`, `gtk.cursorTheme` blocks.
5. In `dconf.settings`, remove the same sub-sections as listed for desktop (Step 2, item 5).
6. Keep all of:
   - `org/gnome/shell.enabled-extensions` (11 extensions, no gamemode)
   - `org/gnome/shell.favorite-apps`
   - `org/gnome/desktop/background.picture-uri` and `picture-uri-dark`
   - All `org/gnome/desktop/app-folders` blocks (Office, Utilities, System)

---

### Step 4: Update `home-htpc.nix`

**Action:** Add import, remove now-shared declarations, ADD missing `enabled-extensions`, keep role-specific content.

Changes:
1. Add `imports = [ ./home/gnome-common.nix ];` (new top-level imports block).
2. Remove entire `home.pointerCursor` block.
3. Remove `gtk.enable`, `gtk.iconTheme`, `gtk.cursorTheme` blocks.
4. In `dconf.settings."org/gnome/shell"`, **ADD** the missing `enabled-extensions` key:

```nix
"org/gnome/shell" = {
  enabled-extensions = [
    "appindicatorsupport@rgcjonas.gmail.com"
    "dash-to-dock@micxgx.gmail.com"
    "AlphabeticalAppGrid@stuarthayhurst"
    # gamemode-shell-extension omitted — programs.gamemode not enabled on htpc
    "gnome-ui-tune@itstime.tech"
    "nothing-to-say@extensions.gnome.wouter.bolsterl.ee"
    "steal-my-focus-window@steal-my-focus-window"
    "tailscale-status@maxgallup.github.com"
    "caffeine@patapon.info"
    "restartto@tiagoporsch.github.io"
    "blur-my-shell@aunetx"
    "background-logo@fedorahosted.org"
  ];
  favorite-apps = [
    # ... existing list unchanged ...
  ];
};
```

5. In `dconf.settings`, remove the same common sub-sections as listed in Step 2, item 5.
   - Exception: keep `"org/gnome/settings-daemon/plugins/power"` — this is HTPC-only.
6. Keep all of:
   - `org/gnome/shell.enabled-extensions` (newly added 11 extensions, no gamemode)
   - `org/gnome/shell.favorite-apps`
   - `org/gnome/desktop/background.picture-uri` and `picture-uri-dark`
   - `org/gnome/settings-daemon/plugins/power.sleep-inactive-*-type`
   - All `org/gnome/desktop/app-folders` blocks (Office, Utilities, System)

---

### Step 5: Update `home-stateless.nix`

**Action:** Add import to existing imports list, remove now-shared declarations, keep role-specific content.

Changes:
1. Add `./home/gnome-common.nix` to the existing `imports` list (alongside `./home/photogimp.nix`).
2. Remove from `home.packages`: `bibata-cursors`, `kora-icon-theme` (keep all other packages).
3. Remove entire `home.pointerCursor` block.
4. Remove `gtk.enable`, `gtk.iconTheme`, `gtk.cursorTheme` blocks.
5. In `dconf.settings`, remove the same common sub-sections as listed in Step 2, item 5.
6. Keep all of:
   - `org/gnome/shell.enabled-extensions` (11 extensions, no gamemode)
   - `org/gnome/shell.favorite-apps`
   - `org/gnome/desktop/background.picture-uri` and `picture-uri-dark`
   - All `org/gnome/desktop/app-folders` blocks (Office, Utilities, System)

---

## 5. Complete dconf Key Reference After Refactor

### What `home/gnome-common.nix` will declare (inherited by all roles):

```
org/gnome/desktop/interface:
  clock-format = "12h"
  cursor-size  = 24
  cursor-theme = "Bibata-Modern-Classic"
  icon-theme   = "kora"

org/gnome/desktop/wm/preferences:
  button-layout = "appmenu:minimize,maximize,close"

org/gnome/desktop/background:
  picture-options = "zoom"

org/gnome/shell/extensions/dash-to-dock:
  dock-position = "LEFT"

org/fedorahosted/background-logo-extension:
  logo-file         = "/run/current-system/sw/share/pixmaps/vex-background-logo.svg"
  logo-file-dark    = "/run/current-system/sw/share/pixmaps/vex-background-logo-dark.svg"
  logo-always-visible = true

org/gnome/desktop/screensaver:
  lock-enabled = false
  lock-delay   = mkUint32 0

org/gnome/session:
  idle-delay = mkUint32 300
```

### What each role home file will declare (role-specific only):

**Desktop** (`home-desktop.nix`):
```
org/gnome/shell:
  enabled-extensions = [...13 extensions including gamemode...]
  favorite-apps      = [...7 desktop apps...]

org/gnome/desktop/background:
  picture-uri      = "file:///home/nimda/Pictures/Wallpapers/vex-bb-light.jxl"
  picture-uri-dark = "file:///home/nimda/Pictures/Wallpapers/vex-bb-dark.jxl"

org/gnome/desktop/app-folders: (Games, Game Utilities, Office, Utilities, System)
```

**Server** (`home-server.nix`):
```
org/gnome/shell:
  enabled-extensions = [...11 extensions, no gamemode...]
  favorite-apps      = [...5 server apps...]

org/gnome/desktop/background:
  picture-uri      = "file:///home/nimda/Pictures/Wallpapers/vex-bb-light.jxl"
  picture-uri-dark = "file:///home/nimda/Pictures/Wallpapers/vex-bb-dark.jxl"

org/gnome/desktop/app-folders: (Office, Utilities, System)
```

**HTPC** (`home-htpc.nix`):
```
org/gnome/shell:
  enabled-extensions = [...11 extensions, no gamemode...] ← NEWLY ADDED
  favorite-apps      = [...8 htpc media apps...]

org/gnome/desktop/background:
  picture-uri      = "file:///home/nimda/Pictures/Wallpapers/vex-bb-light.jxl"
  picture-uri-dark = "file:///home/nimda/Pictures/Wallpapers/vex-bb-dark.jxl"

org/gnome/settings-daemon/plugins/power:
  sleep-inactive-ac-type      = "nothing"
  sleep-inactive-battery-type = "nothing"

org/gnome/desktop/app-folders: (Office, Utilities, System)
```

**Stateless** (`home-stateless.nix`):
```
org/gnome/shell:
  enabled-extensions = [...11 extensions, no gamemode...]
  favorite-apps      = [...5-6 stateless apps...]

org/gnome/desktop/background:
  picture-uri      = "file:///home/nimda/Pictures/Wallpapers/vex-bb-light.jxl"
  picture-uri-dark = "file:///home/nimda/Pictures/Wallpapers/vex-bb-dark.jxl"

org/gnome/desktop/app-folders: (Office, Utilities, System)
```

---

## 6. Server Branding Wiring — Confirmation

As established in Section 1.3, server branding is **already complete**. No changes are required to:
- `configuration-server.nix`
- `modules/branding.nix`
- `home-server.nix` wallpaper file declarations
- Any `files/` or `wallpapers/` asset directories

The implementation subagent should confirm this remains intact after the home-file refactoring and verify no server-specific dconf or branding key is accidentally dropped.

---

## 7. Files to Modify

| File | Action |
|------|--------|
| `home/gnome-common.nix` | **CREATE** — new shared Home Manager sub-module |
| `home-desktop.nix` | **MODIFY** — add import, remove shared blocks |
| `home-server.nix` | **MODIFY** — add import, remove shared blocks |
| `home-htpc.nix` | **MODIFY** — add import, remove shared blocks, ADD enabled-extensions |
| `home-stateless.nix` | **MODIFY** — add import, remove shared blocks |

**Files that MUST NOT be modified:**
- `modules/branding.nix` (server branding already complete)
- `configuration-server.nix` (server branding already complete)
- `flake.nix` (no structural changes needed)
- Any `files/` or `wallpapers/` asset files

---

## 8. Risks and Mitigations

### Risk 1: dconf Key Conflict on Merge

**Risk:** If a key appears in both `home/gnome-common.nix` and a role home file, Home Manager will throw an evaluation conflict.

**Mitigation:** The implementation subagent MUST audit each role home file immediately after edit to confirm no key is declared in both the common module and the role file. The removed keys list in Steps 2–5 is exhaustive. Particular attention: `org/gnome/desktop/background` — the common module sets `picture-options` only; role files set `picture-uri` and `picture-uri-dark` only.

### Risk 2: HTPC Regression on Extension State

**Risk:** Adding `enabled-extensions` to HTPC may enable extensions that conflict with HTPC media-centre usage.

**Mitigation:** The 11-extension list (same as server/stateless) has been validated on similar roles without issue. `gamemodeshellextension` is intentionally excluded. The `appindicator` and `caffeine` extensions are beneficial for HTPC. No regression expected.

### Risk 3: Home Manager `home.packages` Duplicate Declaration

**Risk:** If a role home file already declares `bibata-cursors` or `kora-icon-theme` in `home.packages` AND the common module also does, there may be a conflict.

**Mitigation:** Home Manager deduplicates `home.packages` lists through `lib.mkMerge — duplicate entries in different modules are safe (they become a single entry). However, to keep the code clean, the implementation SHOULD still remove `bibata-cursors` and `kora-icon-theme` from individual role `home.packages` lists when adding the common module import.

### Risk 4: HTPC `home.packages` — No Explicit Package List

**Risk:** `home-htpc.nix` currently has no `home.packages` block. The common module adds `bibata-cursors` and `kora-icon-theme`. These were previously auto-installed via `gtk.iconTheme.package` and `home.pointerCursor.package`. Explicit declaration in the common module is redundant but harmless.

**Mitigation:** No action needed. Home Manager handles duplicate package sources gracefully.

### Risk 5: `nix flake check` Evaluation

**Risk:** After adding a new `home/gnome-common.nix` module with `lib.gvariant.*` calls (`mkUint32`), the evaluator must be able to resolve those GVariant helpers in the Home Manager module context.

**Mitigation:** `lib.gvariant` is available in Home Manager module context (it is the `lib` passed via `specialArgs → useGlobalPkgs`). Existing role home files already use `lib.gvariant.mkUint32` successfully — the common module uses the same `lib` parameter from the standard module arg `{ pkgs, lib, ... }`.

### Risk 6: Missing `enabled-extensions` on HTPC — Existing Installs

**Risk:** Adding `enabled-extensions` to an existing HTPC installation will write the extension UUIDs to the user dconf DB on the next `nixos-rebuild switch`. This is **desired behavior** (the fix).

**Mitigation:** No user data is lost. The extension UUID list is the same as on server. No rollback concern.

---

## 9. Out of Scope

The following gaps were observed during analysis but are **NOT** part of this change:

1. `configuration-stateless.nix` does not set `system.nixos.distroName` — it inherits the branding.nix default `"VexOS Desktop"`. This is a separate concern.
2. `home-htpc.nix` is missing `home.sessionVariables` (`MOZ_ENABLE_WAYLAND`, `QT_QPA_PLATFORM`), `tmux` config, and `justfile` deployment. These are intentional HTPC design choices and must not be changed here.
3. `home-htpc.nix` does not declare an explicit `home.packages` list (ghostty, terminal utilities). Out of scope.
4. `snapper`, `/etc/nixos/hardware-configuration.nix`, and other unrelated modules are untouched.

---

## 10. Validation Checklist (for Review Phase)

After implementation, the reviewer must confirm:

- [ ] `home/gnome-common.nix` exists and is syntactically valid Nix
- [ ] All four home files import `./home/gnome-common.nix`
- [ ] No dconf key appears in both `home/gnome-common.nix` AND any role home file
- [ ] `home-htpc.nix` now declares `enabled-extensions` in `org/gnome/shell`
- [ ] All four home files still declare `picture-uri` and `picture-uri-dark` for their correct wallpaper paths
- [ ] `home-desktop.nix` still includes the gamemode extension in `enabled-extensions`
- [ ] Server role: `vexos.branding.role = "server"` still present in `configuration-server.nix`
- [ ] Server role: `wallpapers/server/vex-bb-{light,dark}.jxl` still referenced in `home-server.nix`
- [ ] `nix flake check` passes with exit code 0
- [ ] `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd` succeeds
- [ ] `sudo nixos-rebuild dry-build --flake .#vexos-server-amd` succeeds
- [ ] `sudo nixos-rebuild dry-build --flake .#vexos-htpc-amd` succeeds
- [ ] `sudo nixos-rebuild dry-build --flake .#vexos-stateless-amd` succeeds
