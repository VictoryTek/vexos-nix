# GVariant Bare Integer Fix — Specification

**Feature:** `gvariant_fix`  
**Date:** 2026-04-18  
**Status:** Ready for Implementation  

---

## 1. Current State Analysis

### Files Containing `dconf.settings` Blocks

| File | dconf Context | Has Bare Integer? |
|------|---------------|-------------------|
| `home/gnome-common.nix` | `dconf.settings."org/gnome/desktop/interface"` | **YES** — line 44 |
| `modules/gnome.nix` | `programs.dconf.profiles.user.databases[].settings."org/gnome/desktop/interface"` | **YES** — line 139 |
| `configuration-htpc.nix` | `programs.dconf.profiles.user.databases[].settings."org/gnome/desktop/interface"` | NO (already fixed — uses `lib.gvariant.mkInt32 24`) |
| `home-desktop.nix` | `dconf.settings` (app folders, extensions, favorites) | NO |
| `home-htpc.nix` | `dconf.settings` (app folders, extensions, favorites) | NO |
| `home-server.nix` | `dconf.settings` (app folders, extensions, favorites) | NO |
| `home-stateless.nix` | `dconf.settings` (app folders, extensions, favorites) | NO |

### Bare Integer Occurrences

#### Occurrence 1 — `home/gnome-common.nix`, line 44

```nix
"org/gnome/desktop/interface" = {
  clock-format = "12h";
  cursor-size  = 24;           # ← BARE INTEGER — must be wrapped
  cursor-theme = "Bibata-Modern-Classic";
  icon-theme   = "kora";
};
```

#### Occurrence 2 — `modules/gnome.nix`, line 139

```nix
"org/gnome/desktop/interface" = {
  cursor-theme = "Bibata-Modern-Classic";
  cursor-size  = 24;           # ← BARE INTEGER — must be wrapped
  icon-theme   = "kora";
  clock-format = "12h";
};
```

### Already-Correct Patterns (Reference)

`configuration-htpc.nix` line 114 (already fixed):
```nix
cursor-size  = lib.gvariant.mkInt32 24;
```

`home/gnome-common.nix` lines 74, 78 (already correct):
```nix
lock-delay  = lib.gvariant.mkUint32 0;
idle-delay  = lib.gvariant.mkUint32 300;
```

---

## 2. Problem Definition

### Root Cause

NixOS 25.05 (nixpkgs commit that introduced stricter GVariant enforcement) added a build-time assertion in the Home Manager and NixOS dconf modules. Any bare Nix integer literal used as a dconf value now produces a fatal evaluation error:

```
error: The GVariant type for number "24" is unclear.
Please wrap the value with one of the following, depending on the value type in GSettings schema:
- `lib.gvariant.mkInt32` for `i`
- `lib.gvariant.mkUint32` for `u`
...
```

Previously, bare integers were silently coerced to `int32`. The new strict mode requires every numeric dconf value to be unambiguously typed at evaluation time.

### Why All Six Desktop Variants Fail

All six failing configurations (`vexos-desktop-amd`, `vexos-desktop-nvidia`, `vexos-desktop-nvidia-legacy535`, `vexos-desktop-nvidia-legacy470`, `vexos-desktop-vm`, `vexos-desktop-intel`) import `configuration-desktop.nix`, which imports `modules/gnome.nix`. The `cursor-size = 24;` bare integer at `modules/gnome.nix` line 139 is therefore evaluated for every desktop variant, producing the same error on all of them.

The `home/gnome-common.nix` bare integer would additionally affect home-manager activation for the desktop, server, stateless, and HTPC roles, but the CI error surface is the nixpkgs-level NixOS evaluation of `modules/gnome.nix`, which is the primary failure point.

### GSettings Schema Type for `cursor-size`

The key `cursor-size` lives in schema `org.gnome.desktop.interface` (source: `gsettings-desktop-schemas`). Its GVariant type is `i` (signed 32-bit integer). The correct Home Manager / NixOS `lib.gvariant` wrapper is therefore `lib.gvariant.mkInt32`.

Reference: [gsettings-desktop-schemas — org.gnome.desktop.interface.gschema.xml.in](https://gitlab.gnome.org/GNOME/gsettings-desktop-schemas/-/blob/main/schemas/org.gnome.desktop.interface.gschema.xml.in)

Confirmed by the already-working pattern in `configuration-htpc.nix` line 114:  
`cursor-size = lib.gvariant.mkInt32 24;`

---

## 3. Proposed Fix

Two single-line changes. Both replace the bare integer `24` with `lib.gvariant.mkInt32 24`.

### Change 1 — `home/gnome-common.nix`

**File:** `home/gnome-common.nix`  
**Line:** 44  
**Schema:** `org.gnome.desktop.interface`  
**Key:** `cursor-size`  
**GVariant type:** `i` → `lib.gvariant.mkInt32`

Before:
```nix
      cursor-size  = 24;
```

After:
```nix
      cursor-size  = lib.gvariant.mkInt32 24;
```

### Change 2 — `modules/gnome.nix`

**File:** `modules/gnome.nix`  
**Line:** 139  
**Schema:** `org.gnome.desktop.interface`  
**Key:** `cursor-size`  
**GVariant type:** `i` → `lib.gvariant.mkInt32`

Before:
```nix
            cursor-size  = 24;
```

After:
```nix
            cursor-size  = lib.gvariant.mkInt32 24;
```

---

## 4. Implementation Steps

1. Edit `home/gnome-common.nix`: replace `cursor-size = 24;` with `cursor-size = lib.gvariant.mkInt32 24;` in the `dconf.settings."org/gnome/desktop/interface"` block.

2. Edit `modules/gnome.nix`: replace `cursor-size = 24;` with `cursor-size = lib.gvariant.mkInt32 24;` in the `programs.dconf.profiles.user.databases[].settings."org/gnome/desktop/interface"` block.

3. No imports, dependency changes, or new packages are required. `lib.gvariant` is part of nixpkgs `lib` and is available in all NixOS and Home Manager module contexts where `lib` is in scope.

4. No `flake.lock` changes needed.

---

## 5. Verification

After applying the two changes, run:

```bash
nix flake check
sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd
sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia
sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm
```

All four commands must complete without the GVariant error.

---

## 6. Risks and Mitigations

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| `lib.gvariant.mkInt32` not available in older nixpkgs | None — project targets NixOS 25.05+ where `lib.gvariant` is stable | N/A |
| Wrong GVariant type chosen (e.g., mkUint32 instead of mkInt32) | Low — schema type `i` is unambiguously signed int32; HTPC config confirms `mkInt32` works | Verified against upstream schema and existing correct usage in `configuration-htpc.nix` |
| Other bare integers missed | Very low — exhaustive grep of all `.nix` files found only these two occurrences | Full-repo grep confirmed no other bare integers inside `dconf.settings` blocks |
| Regression in home-manager cursor size behaviour | None — value 24 is unchanged, only the type annotation is added | Identical cursor size at runtime |

---

## 7. Modified Files

- `home/gnome-common.nix`
- `modules/gnome.nix`

No other files require changes.
