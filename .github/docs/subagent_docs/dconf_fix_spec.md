# dconf Fix Specification
**Status:** DRAFT — Phase 1 Research & Specification  
**Created:** 2026-03-27  
**Scope:** All three nixosConfigurations (`vexos-amd`, `vexos-nvidia`, `vexos-vm`, `vexos-intel`)

---

## 1. Problem Statement

After recent changes to the vexos-nix configuration, **most GNOME dconf customizations
defined in `home.nix` no longer get applied** when the system is running. This affects
GNOME Shell extensions, wallpaper, icon/cursor theme, app-folder organization, clock
format, screensaver settings, and the Dash-to-Dock position — essentially every setting
written by home-manager's `dconf.settings` block in `home.nix`.

---

## 2. Current State Analysis

### 2.1 Where dconf settings live

| File | What it configures | Level |
|------|--------------------|-------|
| `home.nix` lines 143–277 | All GNOME user preferences (`dconf.settings = { … }`) | **Home-Manager (user)** |
| `modules/branding.nix` lines 112–122 | GDM login-screen logo (`programs.dconf.profiles.gdm`) | **NixOS (system)** |
| `modules/gnome.nix` | No dconf settings present | — |
| `configuration.nix` | No dconf settings present | — |

### 2.2 Home-Manager wiring (flake.nix)

```nix
# flake.nix — homeManagerModule (lines 71-82)
homeManagerModule = {
  imports = [ home-manager.nixosModules.home-manager ];
  home-manager = {
    useGlobalPkgs    = true;
    useUserPackages  = true;
    extraSpecialArgs = { inherit inputs; };
    users.nimda      = import ./home.nix;     # ← correct user
  };
};
```

`homeManagerModule` is included in `commonModules`, which is applied to every
`nixosConfigurations` output. The wiring itself is correct.

### 2.3 dconf infrastructure (NixOS-level)

- `services.desktopManager.gnome.enable = true` in `modules/gnome.nix` (line 52).
- The GNOME NixOS module unconditionally sets `programs.dconf.enable = true`
  (confirmed: `nixos/modules/services/desktop-managers/gnome.nix`, line 323).
- `programs.dconf.profiles.gdm` is defined in `modules/branding.nix` (lines 112–122).

### 2.4 What the NixOS dconf module actually does

Source: `nixos/modules/programs/dconf.nix` (nixpkgs main/25.11):

```nix
config = lib.mkIf (cfg.profiles != { } || cfg.enable) {
  programs.dconf.packages = lib.mapAttrsToList mkDconfProfile cfg.profiles;

  environment.etc.dconf = lib.mkIf (cfg.packages != [ ]) {
    source = pkgs.symlinkJoin {
      name = "dconf-system-config";
      paths = map (x: "${x}/etc/dconf") cfg.packages;
      nativeBuildInputs = [ (lib.getBin pkgs.dconf) ];
      postBuild = ''
        if test -d $out/db; then dconf update $out/db; fi
      '';
    };
  };

  services.dbus.packages    = [ pkgs.dconf ];
  systemd.packages          = [ pkgs.dconf ];
  environment.systemPackages = [ pkgs.dconf ];

  environment.sessionVariables = lib.mkIf cfg.enable {
    GIO_EXTRA_MODULES = [ "${pkgs.dconf.lib}/lib/gio/modules" ];
  };
};
```

**Critical observation:** `programs.dconf.packages` is populated **only from explicitly
defined `programs.dconf.profiles.*` entries** via `lib.mapAttrsToList mkDconfProfile cfg.profiles`.
Setting `programs.dconf.enable = true` alone **does not** generate `/etc/dconf/profile/user`.
That file is only created when `programs.dconf.profiles.user` is explicitly defined.

---

## 3. Root Cause Analysis

### ✦ ROOT CAUSE 1 — PRIMARY (HIGH CONFIDENCE)
**`home-manager.backupFileExtension` is not set; `programs.bash.enable = true` creates a `~/.bashrc` collision that silently aborts home-manager activation before dconf is written.**

**Affected file:** `flake.nix`, `homeManagerModule` block (lines 71–82)

**Mechanism:**

1. `home.nix` enables `programs.bash` (line ~54), which causes home-manager to manage
   `~/.bashrc` and `~/.bash_profile` as symlinks into the Nix store.
2. On any existing system where `/home/nimda/.bashrc` already exists as a regular file
   (placed there by NixOS default skel, previous bash usage, or manual editing), home-manager
   detects a collision during the `checkLinkTargets` activation step.
3. Because `home-manager.backupFileExtension` is **not configured** in `homeManagerModule`,
   the activation script exits with a non-zero exit code instead of backing up and replacing
   the file.
4. The `home-manager-nimda.service` systemd user service **fails silently** — `nixos-rebuild switch`
   reports success at the NixOS system level, but the user-level service has not run.
5. The dconf write step (which executes **after** the link-targets step in the activation
   sequence) is **never reached**.
6. **New or changed dconf settings from `home.nix` are never written** to
   `~/.config/dconf/user`.
7. Any dconf settings that existed in the user db from a previous successful activation
   remain intact and continue to work — giving the appearance that "most" (new/changed)
   settings don't apply while a few old ones still do.

**Additional collision candidates** that could trigger the same failure:

| home.nix declaration | Managed path | Likely to pre-exist? |
|----------------------|--------------|----------------------|
| `programs.bash.enable = true` | `~/.bashrc`, `~/.bash_profile` | **Yes** — NixOS creates from skel |
| `xdg.configFile."starship.toml"` | `~/.config/starship.toml` | Yes — if starship was run before HM |
| `home.file."Pictures/Wallpapers/vex-bb-light.jxl"` | `~/Pictures/Wallpapers/vex-bb-light.jxl` | Maybe — if user previously downloaded wallpapers |
| `xdg.desktopEntries."org.gnome.Extensions"` | `~/.local/share/applications/org.gnome.Extensions.desktop` | Possible — GNOME Extensions app creates this |
| photogimp icon files (`home/photogimp.nix`) | `~/.local/share/icons/hicolor/*/apps/photogimp.png` | Yes — if GIMP Flatpak was installed previously |

**Why this started "after recent changes":**  
Each time `home.nix` gains a new managed file (wallpaper entries, desktop entries, PhotoGIMP
icons), the set of potential collision targets grows. On a pre-existing system, at least one
of these paths almost certainly already exists, causing activation to abort.

**Evidence in code:**
- `home-manager.backupFileExtension` is absent from the `homeManagerModule` in `flake.nix`
- `programs.bash.enable = true` is present in `home.nix` (line ~54)
- The photogimp module (`home/photogimp.nix`) already has a `cleanupPhotogimpOrphanFiles`
  activation hook (DAG entry *before* `checkLinkTargets`) that removes orphan files for
  **photogimp icons and .desktop** — confirming the author is already aware of the
  collision problem for those specific paths, but the general `backupFileExtension` safety
  net is still missing.

---

### ✦ ROOT CAUSE 2 — SECONDARY (MEDIUM CONFIDENCE)
**`programs.dconf.profiles.gdm` in `modules/branding.nix` overrides the GDM package's
built-in dconf profile, removing the `user-db:user` line that GDM's greeter needs.**

**Affected file:** `modules/branding.nix`, lines 112–122

**Mechanism:**

The GDM package ships a built-in dconf profile at
`${pkgs.gdm}/share/dconf/profile/gdm` containing:
```
user-db:user
file-db:${gdm}/share/gdm/greeter-dconf-defaults
```
(Confirmed: `pkgs/by-name/gd/gdm/package.nix`, `passthru.dconfProfile`)

When `programs.dconf.profiles.gdm` is defined **anywhere** in the NixOS
configuration, the `mkDconfProfile` function in `programs/dconf.nix` generates a
**replacement** `/etc/dconf/profile/gdm` file from the Nix-managed attributes.  The
merged profile from `branding.nix` + the GDM NixOS module is:

- `enableUserDb = false` → NO `user-db:user` line
- `databases = [ branding-logo-entry ]` (the GDM module adds nothing unless `autoSuspend = false`)

The resulting `/etc/dconf/profile/gdm` is:
```
file-db:/nix/store/…-branding-logo-db
```

The GDM greeter-dconf-defaults database (which provides GDM-specific defaults like
auto-suspend and accessibility settings) is **silently dropped** from the profile.  
This does not directly cause user dconf failures, but it is a regression in GDM
behavior introduced by `modules/branding.nix`.

**Why `enableUserDb = false` is set without `lib.mkDefault`:**  
If the GDM NixOS module were ever to explicitly set `programs.dconf.profiles.gdm.enableUserDb`
(it currently does not — it only conditionally adds `databases` entries), two modules
setting the same bool option without `lib.mkDefault`/`lib.mkOverce` would produce a
module-system evaluation error. The current code is technically safe today but is fragile.

---

### ✦ ROOT CAUSE 3 — SECONDARY (LOW-MEDIUM CONFIDENCE)
**`programs.dconf.profiles.user` is not defined anywhere; on NixOS 25.11 with the new
profiles-based dconf module, `/etc/dconf/profile/user` may not be generated.**

**Affected files:** none explicitly — this is a missing declaration

**Mechanism:**

In NixOS 25.11, the `programs/dconf.nix` module generates `/etc/dconf/profile/*` files
only for explicitly defined `programs.dconf.profiles.*` entries.  Because only
`programs.dconf.profiles.gdm` is defined (by `modules/branding.nix`), only
`/etc/dconf/profile/gdm` is emitted.  No `/etc/dconf/profile/user` is generated.

GLib's dconf backend falls back to a hardcoded `user-db:user` profile when no profile
file is found — so home-manager settings in `~/.config/dconf/user` **are** accessible.
However, system-level GSettings defaults installed via `programs.dconf.packages` (e.g.,
GNOME's distro-level favorites) are **not** included in any `system-db` reference in the
user's view, because no user profile file lists a `system-db`.

**Impact:** System defaults (GNOME's distro database) do not layer on top of user settings.
For vexos, all settings are at user level anyway, so this is a lower-priority issue — but
it becomes important if system-level lock/default overrides are added in the future.

---

### ✦ CONTRIBUTING FACTOR — GDM Auto-Login Race Condition
**`services.displayManager.autoLogin` starts a GNOME session before the
`home-manager-nimda` systemd user service has finished writing dconf settings.**

**Affected file:** `modules/gnome.nix`, lines 58–61

**Mechanism:**

With auto-login enabled, GDM bypasses the login screen and starts a GNOME Wayland
session immediately. The GNOME Shell reads some dconf keys (enabled extensions,
icon/cursor theme, wallpaper URI) **at session startup** — before
`home-manager-nimda.service` has had time to run and update `~/.config/dconf/user`.

On the **first` login after a rebuild** where new dconf values are present, GNOME may
read stale values.  After home-manager activation completes in the background, some
settings are applied dynamically (e.g., `gsettings` reacts to live dconf changes), but
others (e.g., GNOME Shell extensions list) require a shell restart.

This is a lesser issue than ROOT CAUSE 1, because even on first login, dconf settings
from the *previous* activation are still in the db.  The race only matters on a
completely fresh system or after the database is wiped.

---

## 4. What Was Working Before vs. What Is Broken Now

| Aspect | Before (no branding.nix, fewer home.nix files) | After ("recent changes") |
|--------|------------------------------------------------|--------------------------|
| `home-manager-nimda.service` | Activated successfully — no collisions | **Fails silently** — collision on `~/.bashrc` or other managed file |
| `~/.config/dconf/user` | Written by HM activation | **Not updated** — activation aborts before dconf step |
| GNOME extensions | Applied from dconf db (previous activation) | Stale / not updated |
| Wallpaper, icon theme, cursor | Applied | Stale / reverting to GNOME defaults |
| App folders, clock format | Applied | Stale / not set |
| GDM greeter defaults | GDM package's built-in profile used | HM-managed profile drops `user-db:user` and greeter-dconf-defaults |

---

## 5. Fix Steps

### Fix 1 — PRIMARY: Add `home-manager.backupFileExtension` to `flake.nix`

**File:** `flake.nix`  
**Location:** Inside the `homeManagerModule` attrset (after `extraSpecialArgs`)

**Change:**
```nix
homeManagerModule = {
  imports = [ home-manager.nixosModules.home-manager ];
  home-manager = {
    useGlobalPkgs    = true;
    useUserPackages  = true;
    extraSpecialArgs = { inherit inputs; };
    users.nimda      = import ./home.nix;
    # Required: prevents activation abort when managed files already exist.
    # Existing non-symlink files are renamed to *.backup before being replaced.
    backupFileExtension = "backup";
  };
};
```

**Why:** Without this, any pre-existing regular file at a path home-manager wants to
manage causes `checkLinkTargets` to exit non-zero, aborting the entire activation
sequence — including the dconf write step.

**After applying this fix**, on the next `nixos-rebuild switch` + session restart (or
`systemctl --user restart home-manager-nimda.service`), home-manager activation will
succeed and all dconf settings in `home.nix` will be written to `~/.config/dconf/user`.

---

### Fix 2 — PRIMARY: Add explicit `programs.dconf.enable = true` to `modules/gnome.nix`

**File:** `modules/gnome.nix`  
**Location:** After `services.xserver.enable = true;` in the GNOME desktop section

**Change (add):**
```nix
# Explicitly enable dconf so the GIO dconf module is loaded and the
# user-level dconf database (~/.config/dconf/user) is consulted by GLib.
# The GNOME NixOS module also sets this, but declaring it here makes the
# dependency explicit and guards against upstream changes.
programs.dconf.enable = true;
```

**Why:** The GNOME module in nixpkgs currently hard-codes `programs.dconf.enable = true`,
but relying on that implicit dependency is fragile. Making it explicit in `modules/gnome.nix`
documents the requirement and ensures it survives upstream refactoring.

---

### Fix 3 — SECONDARY: Add `programs.dconf.profiles.user` to `modules/gnome.nix`

**File:** `modules/gnome.nix`  
**Location:** Below `programs.dconf.enable = true;`

**Change (add):**
```nix
# Declare the user dconf profile explicitly so NixOS generates
# /etc/dconf/profile/user.  This file lists the databases consulted for
# regular user sessions:
#   - user-db:user        → ~/.config/dconf/user  (home-manager writes here)
#   - system-db:local     → /etc/dconf/db/local    (system-level overrides)
# Without this file, dconf falls back to a hardcoded user-db:user default,
# which works but omits any system-db entries added via programs.dconf.packages.
programs.dconf.profiles.user = {
  enableUserDb = true;  # user-db:user (home-manager writes to this)
  databases = [];       # no system-level locks; add here if needed in future
};
```

**Why:** Generates a clean, declarative `/etc/dconf/profile/user` file. Required once
any `system-db:*` entry is needed in the user profile (e.g., for system-level GNOME
defaults or future lock overrides). Safe to add now — with `databases = []` it is
functionally equivalent to dconf's built-in fallback.

---

### Fix 4 — SECONDARY: Fix `programs.dconf.profiles.gdm` in `modules/branding.nix`

**File:** `modules/branding.nix`  
**Location:** Lines 112–122

**Current code:**
```nix
programs.dconf.profiles.gdm = {
  enableUserDb = false;  # GDM system account — no per-user preferences
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

**Replace with:**
```nix
# GDM login-screen logo via the NixOS dconf profiles API.
# NOTE: Defining programs.dconf.profiles.gdm here overrides the GDM
# package's built-in /share/dconf/profile/gdm (which has user-db:user and
# file-db pointing to greeter-dconf-defaults).  We must re-add the GDM
# greeter defaults database so GDM accessibility/suspend defaults are preserved.
programs.dconf.profiles.gdm = {
  enableUserDb = lib.mkDefault false;  # GDM system account — no per-user db
  databases = [
    # Re-include GDM's own greeter defaults (auto-suspend, a11y, etc.).
    # This preserves what the GDM package's built-in profile provided.
    pkgs.gdm
    # Vexos branding: set the GDM login-screen logo to a stable /etc/ path.
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

**Why two changes:**
1. `lib.mkDefault false` on `enableUserDb` — guards against a future module conflict if
   the GDM NixOS module ever explicitly sets `enableUserDb` (currently it does not, but
   the comment in branding.nix already acknowledges the risk). Using `mkDefault` makes
   branding's value overridable without an eval error.
2. `pkgs.gdm` added as the first `databases` entry — re-includes
   `${pkgs.gdm}/share/gdm/greeter-dconf-defaults` in the profile (the GDM package
   exposes this via `passthru.dconfDb`). This restores the supervisor/a11y/auto-suspend
   defaults that the built-in GDM profile provided and that this override currently drops.

> **Note on `pkgs.gdm` in `databases`:** The `databases` list accepts packages as well
> as attrsets. When a package is an element, `mkDconfProfile` calls `checkDconfDb` to
> validate it as a pre-compiled dconf database file.  `pkgs.gdm.dconfDb` (a passthru
> attribute pointing to the database file) should be used instead of bare `pkgs.gdm`.
> The implementer should verify whether `pkgs.gdm` or `pkgs.gdm.dconfDb` is the correct
> reference by checking the GDM package's passthru attributes in the locked nixpkgs.
> If neither resolves cleanly, the databases list may simply omit the GDM defaults entry
> with a TODO comment — the primary branding goal (logo) is still achieved.

---

### Fix 5 — DIAGNOSTIC: Verify activation is succeeding after Fix 1

After applying Fix 1 and rebuilding, run:

```bash
sudo nixos-rebuild switch --flake .#vexos-amd    # (or relevant target)
# Then, in the user session:
systemctl --user status home-manager-nimda.service
journalctl --user -u home-manager-nimda.service --since "5 minutes ago"
```

Expected: service shows `active (exited)` and journal shows no errors.  
If files were backed up: files named `*.backup` will appear in the managed paths
(e.g., `~/.bashrc.backup`). These can be inspected and removed once the content is
confirmed to have been merged into home-manager's managed version.

Also verify dconf settings are applied:

```bash
dconf read /org/gnome/desktop/interface/icon-theme
# Expected: 'kora'
dconf read /org/gnome/shell/enabled-extensions
# Expected: long list of UUIDs
```

---

## 6. Other Issues Found

### 6.1 `pkgs.unstable.gnomeExtensions.restart-to.extensionUuid` in `home.nix`

**File:** `home.nix`, `dconf.settings` for `"org/gnome/shell".enabled-extensions`

The expression `pkgs.unstable.gnomeExtensions.restart-to.extensionUuid` relies on the
`extensionUuid` passthru attribute being present on that package in `nixpkgs-unstable`.
Not all GNOME extension packages in nixpkgs expose this attribute. If it is absent, the
Nix evaluation will abort with `error: attribute 'extensionUuid' missing`.

**Recommendation:** Hardcode the UUID string `"restart-to@system76.com"` (verify against
the GNOME Extensions portal) instead of deriving it from the package. This eliminates
the runtime dependency on an unstable package attribute and makes the declaration more
robust.

### 6.2 `home.stateVersion = "24.05"` with home-manager release-25.11

**File:** `home.nix`, final line

`home.stateVersion` should remain at the value set during initial installation (it is
intentionally NOT bumped on upgrades). A `stateVersion` of `"24.05"` with
`home-manager.url = "github:nix-community/home-manager/release-25.11"` is fine — the
state version is a migration watermark, not a version constraint.  
No change needed.

### 6.3 Auto-login and dconf startup timing

**File:** `modules/gnome.nix`, auto-login block

With `services.displayManager.autoLogin.enable = true`, GNOME starts before
`home-manager-nimda.service` completes. Settings that GNOME reads once at shell
startup (enabled extensions, window decorations) may briefly show old values on the
very first login after a rebuild. This typically self-corrects on the next login or
after `killall -3 gnome-shell`.

No code change is required for the immediate dconf fix, but the issue should be noted
in case the user reports settings not applying consistently after a rebuild.

### 6.4 Missing `asus.nix` import for `intel` and `vm` hosts

**Files:** `hosts/intel.nix`, `hosts/vm.nix`

`hosts/amd.nix` and `hosts/nvidia.nix` both import `../modules/asus.nix` (ASUS hardware
tuning). `hosts/intel.nix` and `hosts/vm.nix` do not. This is likely intentional (Asus
module is hardware-specific), but it should be confirmed. Not related to the dconf issue.

---

## 7. Implementation Checklist

| Priority | File | Change |
|----------|------|--------|
| **P0 — Critical** | `flake.nix` | Add `backupFileExtension = "backup";` to `homeManagerModule.home-manager` |
| **P1 — Important** | `modules/gnome.nix` | Add explicit `programs.dconf.enable = true;` |
| **P1 — Important** | `modules/gnome.nix` | Add `programs.dconf.profiles.user = { enableUserDb = true; databases = []; };` |
| **P2 — Recommended** | `modules/branding.nix` | Use `lib.mkDefault false` for `enableUserDb`; add GDM greeter defaults to databases |
| **P2 — Recommended** | `home.nix` | Hardcode `restart-to` extension UUID instead of `pkgs.unstable.…extensionUuid` |

---

## 8. Files Modified by This Fix

```
flake.nix
modules/gnome.nix
modules/branding.nix
home.nix
```

---

## 9. Risk Assessment

| Fix | Risk | Mitigation |
|-----|------|-----------|
| `backupFileExtension` | Low — only renames pre-existing conflicting files | Review `*.backup` files after rebuild; content is preserved |
| Explicit `programs.dconf.enable` | Very low — already set by GNOME module | Belt-and-suspenders addition; cannot conflict |
| `programs.dconf.profiles.user` | Low — equivalent to dconf's built-in fallback | `databases = []` means no new locks or system overrides |
| `branding.nix` gdm profile | Medium — changes compiled GDM dconf db | Test GDM login screen appearance after rebuild; revert if greeter breaks |
| Hardcoded ext UUID | None — string constant | Verify UUID against GNOME Extensions portal before committing |
