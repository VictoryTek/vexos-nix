# Specification: Branding — System Logos and Plymouth Watermark

**Feature Name:** `logos_plymouth`
**Spec Path:** `.github/docs/subagent_docs/logos_plymouth_spec.md`
**Date:** 2026-03-26
**Status:** Draft

---

## 1. Current State Analysis

### 1.1 NixOS Configuration Audit

The following files were read in full:

| File | Relevant Observations |
|---|---|
| `flake.nix` | Defines three outputs: `vexos-amd`, `vexos-nvidia`, `vexos-vm`. Shared modules include `configuration.nix` + per-host GPU module. `nixpkgs` pinned to `nixos-25.11`. |
| `configuration.nix` | Imports 12 modules. No branding module exists. `system.stateVersion = "25.11"` (MUST NOT CHANGE). |
| `modules/performance.nix` | Contains `boot.plymouth.enable = true` (line 43). No `theme` or `logo` set → defaults: theme = `bgrt`, logo = NixOS snowflake. |
| `modules/gnome.nix` | GNOME desktop stack sourced from nixpkgs-unstable. `services.desktopManager.gnome.enable = true` + GDM Wayland. Auto-activates `programs.dconf.enable = true`. |
| `modules/packages.nix` | Only adds `unstable.brave`. No branding packages. |
| `hosts/amd.nix` | Imports `configuration.nix`, `modules/gpu/amd.nix`, `modules/asus.nix`. |
| `hosts/nvidia.nix` | Imports `configuration.nix`, `modules/gpu/nvidia.nix`, `modules/asus.nix`. |
| `hosts/vm.nix` | Imports `configuration.nix`, `modules/gpu/vm.nix`. Sets `networking.hostName = "vexos-vm"`. |

### 1.2 Files Present in the Repository

**`files/pixmaps/`** — 9 files, originating from a Fedora Silverblue build:

| Filename | Size (bytes) | Inferred Purpose |
|---|---|---|
| `vex.png` | 48,956 | **Primary custom vexos brand logo** (the key custom asset) |
| `system-logo-white.png` | 21,912 | White-on-dark logo variant; byte count matches `fedora-logo-sprite.png` exactly — content must be visually verified before deployment |
| `fedora-gdm-logo.png` | 7,745 | Small Fedora GDM-optimized logo (Fedora-branded) |
| `fedora-logo-small.png` | 9,027 | Small Fedora logo (Fedora-branded) |
| `fedora-logo-sprite.png` | 21,912 | Raster Fedora sprite/web logo (Fedora-branded) |
| `fedora-logo-sprite.svg` | 139,310 | Scalable Fedora sprite logo (Fedora-branded) |
| `fedora-logo.png` | 425,219 | Full-size Fedora logo — large asset (Fedora-branded) |
| `fedora_logo_med.png` | 20,832 | Medium-size Fedora color logo (Fedora-branded) |
| `fedora_whitelogo_med.png` | 20,832 | Medium-size Fedora white logo (Fedora-branded) |

**`files/plymouth/`** — 1 file:

| Filename | Size (bytes) | Purpose |
|---|---|---|
| `watermark.png` | 23,717 | Custom vexos Plymouth boot splash watermark/logo |

### 1.3 What Is Missing

- `boot.plymouth.logo` is not set → Plymouth watermark is the default NixOS snowflake.
- `boot.plymouth.theme` is not set → Plymouth uses `bgrt` (ACPI firmware splash). The `bgrt` theme does **not** use `boot.plymouth.logo`; the `spinner` theme does.
- No NixOS module deploys any file from `files/pixmaps/` to the system. These assets are uninstalled.
- No `modules/branding.nix` exists. Branding configuration is spread across no module at all.

---

## 2. Problem Definition

The user has custom branding assets committed to the repository:
- A custom vexos logo (`vex.png`) and several Fedora-sourced size/format variants.
- A custom Plymouth boot watermark (`watermark.png`).

None of these files are currently deployed to the NixOS system. Two separate integration tasks are needed:

1. **Plymouth watermark**: The boot splash must display `files/plymouth/watermark.png` instead of the NixOS snowflake. This requires both setting the logo path **and** switching from `bgrt` to the `spinner` theme (the only default theme that actually displays `boot.plymouth.logo` as a visible watermark).

2. **System pixmaps**: The custom logos must be deployed to the system's shared data directory so that applications using `XDG_DATA_DIRS` (GNOME applications, GDM, icon lookups) can find custom vexos branding at the standard `share/pixmaps/` path.

3. **(Optional) GDM login-screen logo**: The GDM Wayland greeter can display a custom system logo via the dconf key `org.gnome.login-screen.logo`. This requires a stable (non-store) file path and a GDM dconf profile.

---

## 3. Research Findings

### 3.1 Plymouth — NixOS Module Mechanics

**Source**: `github:NixOS/nixpkgs/nixos-25.05` → `nixos/modules/system/boot/plymouth.nix` (reviewed via GitHub).

The NixOS Plymouth module exposes these options (all confirmed present in NixOS 25.11):

| Option | Type | Default | Notes |
|---|---|---|---|
| `boot.plymouth.enable` | bool | `false` | Already `true` in `modules/performance.nix` |
| `boot.plymouth.theme` | string | `"bgrt"` | Currently unset (uses default) |
| `boot.plymouth.logo` | path | NixOS snowflake PNG | Currently unset (uses default) |
| `boot.plymouth.themePackages` | list of packages | `[]` | Used to supply third-party theme packages |
| `boot.plymouth.font` | path | DejaVuSans.ttf | Not relevant here |
| `boot.plymouth.extraConfig` | string | `""` | Not relevant here |

When `boot.plymouth.logo` is set, the module internally creates a `plymouthLogos` derivation that:
- Symlinks the logo as `watermark.png` into the `spinner` theme directory.
- Symlinks the logo as `header-image.png` into the `spinfinity` theme directory.
- Copies the logo to `/etc/plymouth/logo.png` inside the initrd.

**Critical constraint**: The `bgrt` theme (current default) does **not** display `boot.plymouth.logo`. The `bgrt` theme uses the ACPI firmware splash image. To display the custom watermark, the theme must be explicitly changed to `"spinner"`.

**Format constraint**: `boot.plymouth.logo` must be a PNG file. `files/plymouth/watermark.png` satisfies this.

**VM note**: Plymouth is loaded in all three targets (AMD, NVIDIA, VM) because `boot.plymouth.enable = true` is in `modules/performance.nix` which is imported by all hosts via `configuration.nix`. In VM guests, Plymouth may not render visibly (no native framebuffer in many hypervisors) but this causes no build failure — Plymouth exits gracefully when no drm/framebuffer device is available.

### 3.2 Pixmaps — NixOS Deployment Mechanics

NixOS does not maintain a traditional FHS `/usr/` hierarchy. There is no `/usr/share/pixmaps/`. The NixOS equivalent is:

```
/run/current-system/sw/share/pixmaps/
```

This path is included in `XDG_DATA_DIRS` by default on NixOS. Any application (including GNOME, GTK apps, and GDM) that uses GLib's `g_get_system_data_dirs()` or standard XDG base directory lookups will find files at `share/pixmaps/<name>` relative to any directory in `XDG_DATA_DIRS`.

**Deployment mechanism**: Create a Nix derivation using `pkgs.runCommand` that copies the branding files into `$out/share/pixmaps/`, then add the derivation to `environment.systemPackages`. NixOS merges all packages in `environment.systemPackages` into the current system profile, making them available at `/run/current-system/sw/share/pixmaps/`.

**Why not `environment.etc`**: `environment.etc` is for `/etc/` paths only. Pixmaps belong under `share/pixmaps/`, not `/etc/`. Using `environment.etc` for pixmaps would be incorrect.

**Why not `system.activationScripts`**: Activation scripts are imperative and harder to reproduce declaratively. The `pkgs.runCommand` derivation approach is idiomatic Nix.

### 3.3 Fedora Silverblue Pixmaps — Purpose Mapping

Fedora Silverblue ships a `fedora-logos` package that installs to `/usr/share/pixmaps/`:

| Fedora File | NixOS Primary Consumer | Notes |
|---|---|---|
| `fedora-gdm-logo.png` | GDM greeter system logo | Small icon for login screen header |
| `fedora-logo-small.png` | Applications using small distro logo | 9 KB small variant |
| `fedora-logo-sprite.png` / `.svg` | Web/print, About dialog fallback | Raster + vector sprite |
| `fedora-logo.png` | High-resolution logo | 425 KB — large; typically for print/splash |
| `fedora_logo_med.png` | Medium display contexts | 20 KB color variant |
| `fedora_whitelogo_med.png` | Medium white display (dark backgrounds) | 20 KB white variant |
| `system-logo-white.png` | GDM greeter, GNOME About, login screen | White logo for dark UI backgrounds |

For a vexos deployment, all `fedora-`-prefixed names must be **renamed** with a `vex-` prefix at install time. Only `vex.png` and `system-logo-white.png` are already correctly named.

**Important pre-implementation check**: `system-logo-white.png` (21,912 bytes) is byte-for-byte the same size as `fedora-logo-sprite.png` (21,912 bytes). Before deploying `system-logo-white.png` as vexos branding, the implementer **must visually verify** that this file contains custom vexos artwork and is NOT the vanilla Fedora sprite logo with a rename. If it is the unmodified Fedora image, it should NOT be deployed under `system-logo-white.png`.

### 3.4 GDM Login Screen Logo

GNOME Display Manager (GDM) in GNOME 45+ reads the login-screen logo from the dconf key:
```
org.gnome.login-screen.logo  (type: string, path to PNG file)
```

In NixOS, GDM runs as the system `gdm` user and reads its dconf settings from the dconf profile stored at `/etc/dconf/profile/gdm`. The NixOS option `programs.dconf.profiles.gdm` (confirmed present in NixOS 25.11) creates this profile file automatically.

**Stable path requirement**: Nix store paths (e.g., `/nix/store/<hash>-watermark.png`) change on every rebuild. A dconf string value pointing to a store path would break on every `nixos-rebuild switch`. The solution is to deploy the logo to a stable `/etc/` path first using `environment.etc`, then reference that stable path in the dconf setting.

**Confirmed option syntax** (from `nixos/modules/programs/dconf.nix` source review):
```nix
programs.dconf.profiles.gdm = {
  enableUserDb = false;      # GDM system account; no personal user-db needed
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

Note: `lib.generators.toDconfINI` converts Nix string values to quoted dconf INI strings. Plain Nix strings are correct for the `logo` string key.

---

## 4. Proposed Solution Architecture

### 4.1 Module Layout

Create a new file: **`modules/branding.nix`**

This module is imported by `configuration.nix` (shared by all three host targets) and handles:
- Plymouth theme + logo
- System pixmaps derivation
- (Optional) GDM login-screen logo

**Rationale for a new module rather than editing existing files**:
- `modules/performance.nix` owns boot performance tuning. Branding is separate.
- `modules/gnome.nix` owns the GNOME desktop stack. Branding crosses Plymouth (not GNOME) too.
- A dedicated `modules/branding.nix` is easy to locate, remove, or override per-host.

### 4.2 Plymouth Configuration

**In `modules/branding.nix`**:
```nix
# Switch from bgrt (ACPI firmware splash) to spinner (supports custom watermark).
# boot.plymouth.enable is deliberately kept in modules/performance.nix.
boot.plymouth.theme = lib.mkDefault "spinner";
boot.plymouth.logo  = ../files/plymouth/watermark.png;
```

Using `lib.mkDefault` allows a specific host (e.g., a machine that wants `bgrt`) to override the theme without conflict.

### 4.3 Pixmaps Derivation

**File deployment mapping** (source → installed name → rationale):

| Source File | Installed Name | XDG Path | Rationale |
|---|---|---|---|
| `files/pixmaps/vex.png` | `vex.png` | `share/pixmaps/vex.png` | Primary brand logo under its natural name |
| `files/pixmaps/vex.png` | `distributor-logo.png` | `share/pixmaps/distributor-logo.png` | Standard name apps use for distro logo lookup |
| `files/pixmaps/system-logo-white.png` | `system-logo-white.png` | `share/pixmaps/system-logo-white.png` | Standard name GDM/GNOME uses for dark-background system logo |
| `files/pixmaps/fedora-gdm-logo.png` | `vex-gdm-logo.png` | `share/pixmaps/vex-gdm-logo.png` | GDM-optimized small logo (renamed from fedora) |
| `files/pixmaps/fedora-logo-small.png` | `vex-logo-small.png` | `share/pixmaps/vex-logo-small.png` | Small logo variant (renamed) |
| `files/pixmaps/fedora-logo-sprite.png` | `vex-logo-sprite.png` | `share/pixmaps/vex-logo-sprite.png` | Sprite raster logo (renamed) |
| `files/pixmaps/fedora-logo-sprite.svg` | `vex-logo-sprite.svg` | `share/pixmaps/vex-logo-sprite.svg` | Sprite scalable logo (renamed) |
| `files/pixmaps/fedora-logo.png` | `vex-logo.png` | `share/pixmaps/vex-logo.png` | Full-size logo (renamed) |
| `files/pixmaps/fedora_logo_med.png` | `vex-logo-med.png` | `share/pixmaps/vex-logo-med.png` | Medium color logo (renamed) |
| `files/pixmaps/fedora_whitelogo_med.png` | `vex-whitelogo-med.png` | `share/pixmaps/vex-whitelogo-med.png` | Medium white logo (renamed) |

**Nix derivation expression** (in `modules/branding.nix`):
```nix
let
  vexosLogos = pkgs.runCommand "vexos-logos" {} ''
    mkdir -p $out/share/pixmaps

    # Primary brand logo (deployed under two names)
    cp ${../files/pixmaps/vex.png}                   $out/share/pixmaps/vex.png
    cp ${../files/pixmaps/vex.png}                   $out/share/pixmaps/distributor-logo.png

    # White variant for dark backgrounds / GDM standard name
    cp ${../files/pixmaps/system-logo-white.png}     $out/share/pixmaps/system-logo-white.png

    # Size/format variants — renamed from fedora- to vex-
    cp ${../files/pixmaps/fedora-gdm-logo.png}       $out/share/pixmaps/vex-gdm-logo.png
    cp ${../files/pixmaps/fedora-logo-small.png}     $out/share/pixmaps/vex-logo-small.png
    cp ${../files/pixmaps/fedora-logo-sprite.png}    $out/share/pixmaps/vex-logo-sprite.png
    cp ${../files/pixmaps/fedora-logo-sprite.svg}    $out/share/pixmaps/vex-logo-sprite.svg
    cp ${../files/pixmaps/fedora-logo.png}           $out/share/pixmaps/vex-logo.png
    cp ${../files/pixmaps/fedora_logo_med.png}       $out/share/pixmaps/vex-logo-med.png
    cp ${../files/pixmaps/fedora_whitelogo_med.png}  $out/share/pixmaps/vex-whitelogo-med.png
  '';
in
```

**How Nix path interpolation works here**: When `${../files/pixmaps/vex.png}` is evaluated in a derivation string, Nix copies the referenced file into the Nix store and substitutes its store path (e.g., `/nix/store/<hash>-vex.png`). The relative path `../files/pixmaps/...` is resolved relative to `modules/branding.nix` at evaluation time — this is the standard Nix mechanism for referencing local files in derivations.

### 4.4 GDM Login-Screen Logo (Optional Enhancement)

**Deployment in `modules/branding.nix`** (mark as optional — see Risk 3):
```nix
# Deploy logo at a stable /etc/ path so GDM dconf can reference it
# without the path changing on every nixos-rebuild.
environment.etc."vexos/gdm-logo.png".source = ../files/pixmaps/system-logo-white.png;

# GDM dconf profile: sets the login screen logo.
# org.gnome.login-screen.logo is the GDM 45+ dconf key for the greeter logo.
programs.dconf.profiles.gdm = {
  enableUserDb = false;  # GDM system account — no personal user preferences
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

**If the `programs.dconf.profiles.gdm` key conflicts with a key already set by the GNOME NixOS module** (some versions of GNOME's NixOS module may configure the gdm dconf profile themselves), wrap the whole block with comments and note it as needing manual verification.

### 4.5 Complete `modules/branding.nix`

```nix
# modules/branding.nix
# Custom vexos branding: Plymouth boot watermark and system pixmaps logos.
# Optionally sets the GDM login-screen logo via dconf.
{ pkgs, lib, ... }:
let
  vexosLogos = pkgs.runCommand "vexos-logos" {} ''
    mkdir -p $out/share/pixmaps

    # Primary brand logo
    cp ${../files/pixmaps/vex.png}                   $out/share/pixmaps/vex.png
    cp ${../files/pixmaps/vex.png}                   $out/share/pixmaps/distributor-logo.png

    # White variant (dark-background logo)
    cp ${../files/pixmaps/system-logo-white.png}     $out/share/pixmaps/system-logo-white.png

    # Size/format variants (renamed fedora- → vex-)
    cp ${../files/pixmaps/fedora-gdm-logo.png}       $out/share/pixmaps/vex-gdm-logo.png
    cp ${../files/pixmaps/fedora-logo-small.png}     $out/share/pixmaps/vex-logo-small.png
    cp ${../files/pixmaps/fedora-logo-sprite.png}    $out/share/pixmaps/vex-logo-sprite.png
    cp ${../files/pixmaps/fedora-logo-sprite.svg}    $out/share/pixmaps/vex-logo-sprite.svg
    cp ${../files/pixmaps/fedora-logo.png}           $out/share/pixmaps/vex-logo.png
    cp ${../files/pixmaps/fedora_logo_med.png}       $out/share/pixmaps/vex-logo-med.png
    cp ${../files/pixmaps/fedora_whitelogo_med.png}  $out/share/pixmaps/vex-whitelogo-med.png
  '';
in
{
  # ── Plymouth boot splash ──────────────────────────────────────────────────
  # Switch from bgrt (ACPI firmware splash, does not show logo) to spinner
  # (displays boot.plymouth.logo as a centered watermark).
  # boot.plymouth.enable is set in modules/performance.nix.
  boot.plymouth.theme = lib.mkDefault "spinner";
  boot.plymouth.logo  = ../files/plymouth/watermark.png;

  # ── System pixmaps logos ──────────────────────────────────────────────────
  # Deploys branding files into /run/current-system/sw/share/pixmaps/.
  # XDG_DATA_DIRS includes /run/current-system/sw/share, so all GLib/GTK
  # applications resolve these via standard g_get_system_data_dirs() lookups.
  environment.systemPackages = [ vexosLogos ];

  # ── GDM login-screen logo (optional) ─────────────────────────────────────
  # Provides a stable /etc path for the logo so the dconf value does not
  # change with every nixos-rebuild (store paths are rebuild-variant).
  environment.etc."vexos/gdm-logo.png".source = ../files/pixmaps/system-logo-white.png;

  programs.dconf.profiles.gdm = {
    enableUserDb = false;
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
}
```

### 4.6 Changes to `configuration.nix`

Add exactly **one line** to the `imports` list in `configuration.nix`:

```nix
imports = [
  ./modules/gnome.nix
  ./modules/packages.nix
  ./modules/gaming.nix
  ./modules/audio.nix
  ./modules/gpu.nix
  ./modules/performance.nix
  ./modules/controllers.nix
  ./modules/flatpak.nix
  ./modules/network.nix
  ./modules/development.nix
  ./modules/virtualization.nix
  ./modules/branding.nix   # ← ADD THIS LINE
];
```

No other changes to `configuration.nix` are required or permitted.

---

## 5. Implementation Steps (Ordered)

### Step 1 — Visual Audit of Source Files

**Before writing any Nix code**, the implementer must:

1. Open `files/pixmaps/system-logo-white.png` in an image viewer.
   - **If it contains Fedora branding**: do NOT deploy it as `system-logo-white.png`. Comment out or remove the `system-logo-white.png` line from the derivation. Notify the user.
   - **If it contains custom vexos artwork**: proceed as specified.

2. Open each `fedora-*` file. If any file contains only generic vexos artwork and NOT Fedora branding (e.g., the filename was repurposed), update the spec note to reflect that. Otherwise, they must be deployed under `vex-*` names only as specified.

3. Verify `files/plymouth/watermark.png` opens as a valid PNG (not corrupt).

### Step 2 — Create `modules/branding.nix`

Create the file at `c:\Projects\vexos-nix\modules\branding.nix` with the complete content from Section 4.5.

**Notes**:
- The relative paths `${../files/...}` are correct when the module lives at `modules/branding.nix`.
- Do NOT add a `config.` or `pkgs.` prefix to `boot.plymouth.logo` path — Nix path literals are not strings.

### Step 3 — Add Import to `configuration.nix`

Edit `configuration.nix`'s `imports = [ ... ]` block to add `./modules/branding.nix` as the last entry (see Section 4.6).

### Step 4 — Handle GDM dconf Conflict (If Any)

After adding the import, run `nix flake check`. If evaluation fails with an error about `programs.dconf.profiles.gdm` being defined multiple times, it means the GNOME NixOS module already declares this profile. In that case:

1. Remove the `programs.dconf.profiles.gdm` block from `modules/branding.nix`.
2. Keep `environment.etc."vexos/gdm-logo.png".source = ...`.
3. Add the GDM logo setting as a system-level `programs.dconf.packages` entry instead, OR defer it to home-manager's `dconf.settings` (GDM cannot read home-manager user config).
4. Document this in `.github/docs/subagent_docs/logos_plymouth_spec.md` as a known limitation.

### Step 5 — `nix flake check`

```bash
nix flake check
```

Must exit 0. Fix any evaluation errors before proceeding.

### Step 6 — Dry-build All Three Targets

```bash
sudo nixos-rebuild dry-build --flake .#vexos-amd
sudo nixos-rebuild dry-build --flake .#vexos-nvidia
sudo nixos-rebuild dry-build --flake .#vexos-vm
```

All three must succeed. A dry-build validates that:
- All Nix path references in the branding derivation resolve correctly.
- The Plymouth logo path is found and is a valid Nix path.
- No module option conflicts exist.

### Step 7 — Verify Plymouth Logo in Store (Optional, Strongly Recommended)

After a successful dry-build, confirm the Plymouth derivation includes the custom logo:

```bash
nix-store --query --references \
  $(nix build .#nixosConfigurations.vexos-amd.config.system.build.toplevel --no-link --print-out-paths) \
  | grep plymouth
```

Or inspect the built system closure to confirm `bootlogo` / `plymouthLogos` derivation references `watermark.png` from the repo.

---

## 6. Risks and Mitigations

### Risk 1 — `bgrt` → `spinner` Theme Switch

**Risk**: Systems where the UEFI firmware provides a native ACPI splash via `bgrt` will lose that splash in favor of `spinner`. Some users prefer `bgrt` for cleaner boot transitions.

**Mitigation**: Using `lib.mkDefault "spinner"` allows a host-level override in any `hosts/*.nix` file:
```nix
boot.plymouth.theme = lib.mkForce "bgrt";
```
This is low risk — `spinner` is the Plymouth upstream default and is universally supported.

### Risk 2 — `system-logo-white.png` Contains Fedora Artwork

**Risk**: The `system-logo-white.png` file is the same byte size as `fedora-logo-sprite.png`. If the file is the unmodified Fedora sprite logo, deploying it as `system-logo-white.png` places Fedora branding in the vexos system.

**Mitigation**: Step 1 of the implementation requires visual verification. If the file is Fedora-branded, remove the `system-logo-white.png` install line from the derivation. The GDM optional section references this file — also remove/adjust accordingly.

### Risk 3 — `programs.dconf.profiles.gdm` Conflict

**Risk**: In NixOS 25.11 with GNOME enabled, the system may already configure a `gdm` dconf profile internally (e.g., for GNOME Shell accessibility settings). Defining `programs.dconf.profiles.gdm` in `branding.nix` could conflict.

**Mitigation**: See Step 4 in the implementation steps. The GDM logo section is explicitly **optional** — Plymouth and pixmaps are the primary deliverables. If the dconf profile conflicts, remove the optional block without affecting the rest.

### Risk 4 — Fedora-Named Artifacts Deployed as vexos Branding

**Risk**: If `fedora-*` filenames are deployed verbatim, future maintainers see `fedora-gdm-logo.png` in the running system, which is confusing and incorrect.

**Mitigation**: The derivation renames all `fedora-*` source files to `vex-*` at install time. Source files retain original names in git (preserving history and origin context). No `fedora-*` name appears under `/run/current-system/sw/share/pixmaps/`.

### Risk 5 — Large `fedora-logo.png` (425 KB) in the Store

**Risk**: A 425 KB raster Logo may be surprising in the Nix store, though it is not unusual.

**Mitigation**: The Nix store is designed to handle arbitrary file sizes. The file adds ≤1 MB to the store (compressed). Plymouth uses only `watermark.png` (23.7 KB) — the large raster logo is purely for application consumption, not initrd. No initrd size impact.

### Risk 6 — Plymouth in VM Guests

**Risk**: Plymouth's `spinner` theme in a VM guest may produce a blank/garbled screen or no splash at all, depending on the hypervisor's framebuffer support.

**Mitigation**: Plymouth gracefully exits if no supported display device is found. The `vexos-vm` dry-build confirms the configuration evaluates correctly. Visually, Plymouth may not appear in VMs — this is expected and acceptable behavior.

### Risk 7 — GDM Logo Path Stability

**Risk**: If the GDM optional section uses a Nix store path directly (instead of `environment.etc`), the logo breaks on every rebuild.

**Mitigation**: The spec explicitly routes the logo through `environment.etc."vexos/gdm-logo.png"` which is a stable, rebuild-invariant `/etc/` path. This is mandatory for any dconf string value referencing a file.

### Risk 8 — Plymouth `logo` Path Relative Resolution

**Risk**: If the path `../files/plymouth/watermark.png` in `modules/branding.nix` is resolved incorrectly, Plymouth evaluation fails.

**Mitigation**: NixOS path literals in module files are resolved relative to the module file's directory at load time. `modules/branding.nix` is at `modules/`, so `../files/plymouth/watermark.png` → `files/plymouth/watermark.png` relative to the repo root — correct. Confirmed by how other modules reference `../files/starship.toml`.

---

## 7. NixOS-Specific Constraints

The following constraints were verified during the audit and must be respected by the implementer:

1. **`hardware-configuration.nix` MUST NOT be added to this repository.** It remains at `/etc/nixos/hardware-configuration.nix` on each host.

2. **`system.stateVersion = "25.11"` MUST NOT be changed.** This value was set at initial installation.

3. **All three targets (`vexos-amd`, `vexos-nvidia`, `vexos-vm`) must dry-build successfully.** The branding module is imported by `configuration.nix` which is shared by all three hosts — any evaluation error in `modules/branding.nix` breaks all targets simultaneously.

4. **`boot.plymouth.enable` stays in `modules/performance.nix`.** The new `modules/branding.nix` only adds `theme` and `logo`. NixOS merges these options at evaluation time — no conflict.

5. **Nix path interpolation `${../files/...}` in `pkgs.runCommand`** adds the file as a build input to the derivation. This is the correct, idiomatic Nix pattern shown in the upstream Plymouth module. It must NOT be replaced with a string path.

6. **`boot.plymouth.logo` must be a `types.path`**, not a string. Write it as a bare Nix path literal (e.g., `../files/plymouth/watermark.png`), not `"${toString ../files/plymouth/watermark.png}"`.

7. **The `lib.mkDefault` wrapper on `boot.plymouth.theme`** allows `modules/gpu/vm.nix` or any host file to override the theme if needed (e.g., VMs that want `text` mode).

8. **No new flake inputs** are introduced by this feature. All required functionality (`pkgs.runCommand`, `environment.etc`, `programs.dconf.profiles`, `boot.plymouth.*`) is provided by nixpkgs NixOS modules already in use.

---

## 8. Summary of Deliverables

| Deliverable | File | Type | Priority |
|---|---|---|---|
| Plymouth watermark | `modules/branding.nix` (new) | `boot.plymouth.theme + logo` | **Required** |
| Pixmaps derivation | `modules/branding.nix` (new) | `pkgs.runCommand` + `environment.systemPackages` | **Required** |
| `configuration.nix` import | `configuration.nix` (edit) | 1-line import addition | **Required** |
| GDM login-screen logo | `modules/branding.nix` (new) | `environment.etc` + `programs.dconf.profiles.gdm` | **Optional** |

The implementation adds exactly **1 new file** (`modules/branding.nix`) and **1 line** to `configuration.nix`. No other files are modified.

---

## 9. References

1. NixOS Plymouth module source (nixos-25.05): `github:NixOS/nixpkgs/.../boot/plymouth.nix` — reviewed for `boot.plymouth.logo`, `plymouthLogos` derivation mechanics, and spinner watermark behavior.
2. NixOS dconf module source (nixos-25.05): `github:NixOS/nixpkgs/.../programs/dconf.nix` — reviewed for `programs.dconf.profiles` structure, `enableUserDb`, `databases.settings` serialization.
3. NixOS Wiki — Plymouth: `wiki.nixos.org/wiki/Plymouth` — confirmed theme switching and silent boot patterns.
4. NixOS Options Search (25.11): `search.nixos.org/options?query=boot.plymouth` — confirmed all 9 options including `boot.plymouth.logo` and `boot.plymouth.theme`.
5. NixOS Options Search (25.11): `search.nixos.org/options?query=programs.dconf.profiles` — confirmed option exists in 25.11.
6. Fedora Silverblue branding conventions — `/usr/share/pixmaps/` layout, `system-logo-white.png`, `distributor-logo.png`, `fedora-gdm-logo.png` usage patterns.
