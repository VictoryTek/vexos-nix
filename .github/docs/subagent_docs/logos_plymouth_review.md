# Review: Branding — System Logos and Plymouth Watermark

**Feature Name:** `logos_plymouth`
**Spec Path:** `.github/docs/subagent_docs/logos_plymouth_spec.md`
**Review Date:** 2026-03-26
**Reviewer:** QA Agent
**Verdict:** ✅ PASS (with deferred host-build validation and non-blocking recommendations)

---

## 1. Specification Compliance

### 1.1 Plymouth Configuration

| Requirement | Expected | Actual | Status |
|---|---|---|---|
| `boot.plymouth.theme` | `lib.mkDefault "spinner"` | `lib.mkDefault "spinner"` | ✅ PASS |
| `boot.plymouth.logo` | `../files/plymouth/watermark.png` | `../files/plymouth/watermark.png` | ✅ PASS |
| `boot.plymouth.enable` (kept in performance.nix) | Untouched in branding.nix | Not set in branding.nix | ✅ PASS |

### 1.2 Pixmaps Derivation — Full File Mapping Audit

| Source File (repo) | Installed Name | Spec Requirement | Status |
|---|---|---|---|
| `vex.png` | `vex.png` | `share/pixmaps/vex.png` | ✅ PASS |
| `vex.png` | `distributor-logo.png` | `share/pixmaps/distributor-logo.png` | ✅ PASS |
| `system-logo-white.png` | `system-logo-white.png` | `share/pixmaps/system-logo-white.png` | ✅ PASS |
| `fedora-gdm-logo.png` | `vex-gdm-logo.png` | `share/pixmaps/vex-gdm-logo.png` | ✅ PASS |
| `fedora-logo-small.png` | `vex-logo-small.png` | `share/pixmaps/vex-logo-small.png` | ✅ PASS |
| `fedora-logo-sprite.png` | `vex-logo-sprite.png` | `share/pixmaps/vex-logo-sprite.png` | ✅ PASS |
| `fedora-logo-sprite.svg` | `vex-logo-sprite.svg` | `share/pixmaps/vex-logo-sprite.svg` | ✅ PASS |
| `fedora-logo.png` | `vex-logo.png` | `share/pixmaps/vex-logo.png` | ✅ PASS |
| `fedora_logo_med.png` | `vex-logo-med.png` | `share/pixmaps/vex-logo-med.png` | ✅ PASS |
| `fedora_whitelogo_med.png` | `vex-whitelogo-med.png` | `share/pixmaps/vex-whitelogo-med.png` | ✅ PASS |

All 10 installed names (9 source files, one deployed under two names) match the spec exactly.

### 1.3 Module Import

`./modules/branding.nix` is added as the 12th entry in `configuration.nix`'s imports list. Exactly one line was added; no other changes were made to `configuration.nix`. ✅

### 1.4 GDM Login-Screen Logo (Optional Enhancement)

| Requirement | Expected | Actual | Status |
|---|---|---|---|
| Stable `/etc/` path | `environment.etc."vexos/gdm-logo.png".source` | Implemented | ✅ PASS |
| GDM dconf profile | `programs.dconf.profiles.gdm` with `databases` list | Implemented | ✅ PASS |
| dconf key | `"org/gnome/login-screen" = { logo = "/etc/vexos/gdm-logo.png"; }` | Exact match | ✅ PASS |
| `enableUserDb = false` | `false` | `false` | ✅ PASS |

### 1.5 Spec Content Match

The implementation content is essentially verbatim from spec §4.5. The only delta is expanded comment blocks in the implementation, which add explanation without changing semantics. Spec compliance is **100%** at the functional level.

---

## 2. Nix Syntax & Correctness

### 2.1 Module Argument List

```nix
{ pkgs, lib, ... }:
```

- `pkgs` is used: `pkgs.runCommand` ✅
- `lib` is used: `lib.mkDefault` ✅
- `...` absorbs extra args (config, etc.) ✅

### 2.2 Let-In Block

```nix
let
  vexosLogos = pkgs.runCommand "vexos-logos" {} '' ... '';
in
{ ... }
```

Valid Nix let-in expression. `pkgs.runCommand name attrs script` signature is correct (`name` = string, `attrs` = `{}`, `script` = multiline bash string). ✅

### 2.3 Brace / Bracket Counting

Manual brace analysis of `modules/branding.nix`:

```
{ pkgs, lib, ... }:             ← function argument destructuring (no brace to track)
let
  vexosLogos = pkgs.runCommand "vexos-logos" {} ''  ← opens bash string
    ...
  '';                                               ← closes bash string + semicolon ✅
in
{                                                   ← opens module attrset
  boot.plymouth.theme = lib.mkDefault "spinner";
  boot.plymouth.logo  = ../files/plymouth/watermark.png;
  environment.systemPackages = [ vexosLogos ];      ← list ✅
  environment.etc."vexos/gdm-logo.png".source = ...;
  programs.dconf.profiles.gdm = {                  ← opens record
    enableUserDb = false;
    databases = [                                   ← opens list
      {                                             ← opens list element
        settings = {                                ← opens settings
          "org/gnome/login-screen" = {              ← opens key attrset
            logo = "/etc/vexos/gdm-logo.png";
          };                                        ← closes "org/gnome/login-screen"
        };                                          ← closes settings
      }                                             ← closes list element
    ];                                              ← closes databases list
  };                                                ← closes programs.dconf.profiles.gdm
}                                                   ← closes module attrset
```

All braces, brackets, and semicolons are matched. ✅

### 2.4 Path Expressions and String Interpolation

All file references in the derivation use the `${../path/to/file}` interpolation pattern:

```nix
cp ${../files/pixmaps/vex.png}                   $out/share/pixmaps/vex.png
```

This is **correct** Nix path interpolation. At evaluation time:
- The relative path `../files/pixmaps/vex.png` (from `modules/branding.nix`) resolves to `{repo-root}/files/pixmaps/vex.png` ✅
- Nix copies the file into the store and substitutes the store path ✅
- The dollar-prefix `$out` is a shell variable within the bash derivation (not interpolated by Nix) ✅

The Plymouth logo path is used without string interpolation (it's a direct Nix path value):
```nix
boot.plymouth.logo = ../files/plymouth/watermark.png;
```
This is correct — `boot.plymouth.logo` is a `path`-typed NixOS option, and a bare relative path is the idiomatic way to set it. ✅

### 2.5 Source Asset Verification

All files referenced in the derivation were confirmed present in the repository:

**`files/pixmaps/`** (confirmed by directory listing):
- `fedora-gdm-logo.png` ✅
- `fedora-logo-small.png` ✅
- `fedora-logo-sprite.png` ✅
- `fedora-logo-sprite.svg` ✅
- `fedora-logo.png` ✅
- `fedora_logo_med.png` ✅
- `fedora_whitelogo_med.png` ✅
- `system-logo-white.png` ✅
- `vex.png` ✅

**`files/plymouth/`** (confirmed by directory listing):
- `watermark.png` ✅

No dangling file references. All `cp` source paths will resolve at build time. ✅

### 2.6 `pkgs.runCommand` Build Environment

`pkgs.runCommand` uses `stdenvNoCC` as its build environment. `stdenvNoCC` includes `coreutils` in the build path, which provides `mkdir` and `cp`. Both commands used in the derivation script are available. ✅

---

## 3. NixOS Best Practices

### 3.1 Plymouth Theme Selection

`boot.plymouth.theme = lib.mkDefault "spinner"` is correct on two counts:
- **`"spinner"`** is the only built-in Plymouth theme that reads and displays `boot.plymouth.logo` as a centered watermark. The default `"bgrt"` theme uses the ACPI firmware splash and ignores `boot.plymouth.logo`. The spec details this constraint in §3.1, and the implementation correctly addresses it. ✅
- **`lib.mkDefault`** allows host-level overrides without conflict (e.g., `hosts/vm.nix` can set `boot.plymouth.theme = lib.mkForce "text"` if needed). ✅

### 3.2 Plymouth Enable

`boot.plymouth.enable = true` is present in `modules/performance.nix` (line 43) and is imported by all three host configurations via `configuration.nix`. The separation of concerns is clean: `performance.nix` owns boot performance, `branding.nix` owns visual identity. ✅

### 3.3 Pixmaps via `environment.systemPackages`

Using `environment.systemPackages` to expose a custom derivation is the idiomatic NixOS approach for deploying files to XDG data directories. Alternatives were correctly ruled out:
- `environment.etc` would only reach `/etc/`, not `share/pixmaps/` ✅
- `system.activationScripts` is imperative and non-declarative ✅
The derivation is added as a list element; NixOS `listOf` types concatenate from multiple modules, so no conflict with the base packages defined in `configuration.nix`. ✅

### 3.4 GDM Logo — Stable Path Pattern

Using `environment.etc."vexos/gdm-logo.png"` to deploy the logo to `/etc/vexos/gdm-logo.png` before referencing it in dconf is the correct pattern. Direct store paths (e.g., `/nix/store/<hash>-system-logo-white.png`) would become invalid after `nixos-rebuild switch` since the hash changes with any modification. The stable `/etc/` path avoids this. ✅

### 3.5 `programs.dconf.profiles.gdm` Merge Behavior

`services.desktopManager.gnome.enable = true` (in `modules/gnome.nix`) causes the NixOS GNOME module to also define `programs.dconf.profiles.gdm`. Within the NixOS module system:
- `programs.dconf.profiles` is `types.attrsOf (types.submoduleWith ...)` — the `gdm` key merges from multiple modules. ✅
- `databases` within the profile is `types.listOf` — the module system concatenates list definitions from multiple modules. The GDM system will read both the GNOME module's accessibility settings and the `branding.nix` login-screen logo setting from separate database entries. ✅
- `enableUserDb = false` is consistent with what the GNOME module expects for the system GDM account. ✅

Static analysis indicates no attribute conflict. However, **this must be verified at build time** (see §4).

---

## 4. Build Validation

> **Context**: This review was conducted on Windows. `nix` and `nixos-rebuild` cannot execute on this platform. Static analysis is substituted; all nix-command-based validations are deferred to the NixOS host.

### 4.1 Import Chain (Static Verified)

```
flake.nix
  └── hosts/amd.nix    → configuration.nix → modules/branding.nix ✅
  └── hosts/nvidia.nix → configuration.nix → modules/branding.nix ✅
  └── hosts/vm.nix     → configuration.nix → modules/branding.nix ✅
```

All three output targets receive the branding changes. ✅

### 4.2 Attribute Conflict Analysis (Static)

| Attribute | Set In | Conflict Risk | Assessment |
|---|---|---|---|
| `boot.plymouth.theme` | `branding.nix` only (mkDefault) | None — no other module sets this | ✅ Clean |
| `boot.plymouth.logo` | `branding.nix` only | None — no other module sets this | ✅ Clean |
| `boot.plymouth.enable` | `performance.nix` only | None — not set in branding.nix | ✅ Clean |
| `environment.systemPackages` | `configuration.nix` + `branding.nix` | List — concatenates | ✅ Clean |
| `environment.etc."vexos/gdm-logo.png"` | `branding.nix` only | None — unique key | ✅ Clean |
| `programs.dconf.profiles.gdm` | `branding.nix` + GNOME NixOS module | Submodule merge + list concat | ✅ Expected clean; verify at build |

### 4.3 Deferred Host-Side Validations

The following must be executed on the NixOS host machine before this work is considered deployment-ready:

- [ ] `nix flake check` — validates flake structure and evaluates all three outputs
- [ ] `sudo nixos-rebuild dry-build --flake .#vexos-amd`
- [ ] `sudo nixos-rebuild dry-build --flake .#vexos-nvidia`
- [ ] `sudo nixos-rebuild dry-build --flake .#vexos-vm`
- [ ] Confirm `programs.dconf.profiles.gdm` produces no evaluation conflict with the GNOME module

---

## 5. Constraints Check

| Constraint | Requirement | Status |
|---|---|---|
| `hardware-configuration.nix` not in repo | Must not be committed | ✅ Not present in workspace; only referenced as `/etc/nixos/hardware-configuration.nix` in `flake.nix` |
| `system.stateVersion` unchanged | Must remain `"25.11"` | ✅ Still `"25.11"` in `configuration.nix` (line 140); `branding.nix` does not touch this |
| All three targets receive changes | `vexos-amd`, `vexos-nvidia`, `vexos-vm` | ✅ All import `configuration.nix` which imports `branding.nix` |
| `nixpkgs.follows` for new inputs | No new flake inputs added | ✅ No changes to `flake.nix` |

---

## 6. Security

| Check | Finding | Status |
|---|---|---|
| Hardcoded secrets / credentials | None | ✅ PASS |
| Sensitive data in assets | PNG/SVG/PNG files — static image data only | ✅ PASS |
| Derivation sandbox | `pkgs.runCommand` runs in Nix sandbox; only reads declared inputs | ✅ PASS |
| `/etc/vexos/gdm-logo.png` permissions | Deployed via `environment.etc` — standard NixOS managed path, world-readable, no write access | ✅ PASS |
| SSRF / injection in dconf values | `/etc/vexos/gdm-logo.png` is a literal static string; no interpolation at runtime | ✅ PASS |

---

## 7. Critical Issues

**No CRITICAL issues were found.**

Static analysis reveals fully correct Nix syntax, complete spec compliance, valid file references, clean attribute handling, and no security concerns.

---

## 8. Recommended Improvements (Non-Blocking)

### REC-1: Apply `lib.mkDefault` to `boot.plymouth.logo`

**Current:**
```nix
boot.plymouth.logo = ../files/plymouth/watermark.png;
```

**Recommended:**
```nix
boot.plymouth.logo = lib.mkDefault ../files/plymouth/watermark.png;
```

**Rationale:** `boot.plymouth.theme` uses `lib.mkDefault` to allow host-level overrides. `boot.plymouth.logo` should be consistent — if a host wanted a different logo (e.g., a VM with no custom splash), it would need `lib.mkForce` to override a value without `mkDefault`. Applying `mkDefault` here costs nothing and makes the override story symmetric with `theme`.

---

### REC-2: Visual Verification of `system-logo-white.png`

The spec (§3.2) explicitly flags that `files/pixmaps/system-logo-white.png` (21,912 bytes) is byte-for-byte the **same size** as `files/pixmaps/fedora-logo-sprite.png` (21,912 bytes). This raises the possibility that `system-logo-white.png` may be a renamed copy of the vanilla Fedora logo-sprite rather than custom vexos artwork.

**Action required before production deployment:**
Open `files/pixmaps/system-logo-white.png` in an image viewer and visually confirm it displays vexos branding. If it is the unmodified Fedora image, replace it with actual vexos artwork before going live.

This does not affect build correctness and is not a code issue — it is a content verification requirement noted in the original specification.

---

### REC-3: Plymouth Theme Override for VM Target

`boot.plymouth.theme = lib.mkDefault "spinner"` applies to all three targets, including `vexos-vm`. In a QEMU/KVM or VirtualBox guest, there is typically no DRM framebuffer device, so Plymouth exits silently and the splash does not render. This is harmless but adds a small initrd build cost.

**Optional addition to `hosts/vm.nix`:**
```nix
# Plymouth spinner provides no visual benefit in VM guests (no native framebuffer).
# Use text mode for a cleaner console boot experience.
boot.plymouth.theme = lib.mkForce "text";
```

This is purely cosmetic and does not affect build correctness.

---

### REC-4: GDM Dconf Conflict — Verify at Build

The warning comment in `branding.nix` correctly documents the potential for a `programs.dconf.profiles.gdm` merge conflict with the NixOS GNOME module. Static analysis of the module system's type definitions (`attrsOf` submodule + `listOf` databases) suggests the two definitions will merge correctly without error. However, the exact behavior of `enableUserDb` merging should be confirmed by running `nix flake check` on the host.

If a conflict is reported at evaluation time, the fix is to remove the `programs.dconf.profiles.gdm` block and set the GDM logo via an alternative mechanism (per the fallback noted in the spec §4.4).

---

## Score Table

| Category | Score | Grade | Notes |
|----------|-------|-------|-------|
| Specification Compliance | 98% | A+ | 100% functional match to spec; minor: `logo` lacks `mkDefault` (REC-1) |
| Best Practices | 94% | A | mkDefault on theme ✅; idiomatic runCommand ✅; stable etc path ✅; logo not mkDefault (REC-1) |
| Functionality | 95% | A | All three targets covered; Plymouth, pixmaps, GDM all implemented |
| Code Quality | 96% | A | Clean structure, well-commented, consistent with project style |
| Security | 100% | A+ | No secrets, sandboxed derivation, static assets, stable path for dconf |
| Performance | 92% | A- | Lightweight runCommand derivation; `distributor-logo.png` alias enables future logo lookup optimization; VM Plymouth overhead is minor (REC-3) |
| Consistency | 95% | A | Follows project module conventions; `lib.mkDefault` applied to `theme` but not `logo` (minor asymmetry) |
| Build Success | N/A | Pending | Static analysis: CLEAN — no syntax errors, no attribute conflicts, all file refs valid. Deferred: `nix flake check` + `nixos-rebuild dry-build` on NixOS host required |

**Overall Grade: A (96%)**

---

## Summary

The implementation of `modules/branding.nix` and the corresponding import addition to `configuration.nix` are **correct, complete, and fully compliant with the specification**.

**Key findings:**

- ✅ All 10 pixmap install targets match the spec mapping table exactly
- ✅ Plymouth theme correctly set to `"spinner"` (the only built-in theme that displays `boot.plymouth.logo`)
- ✅ Plymouth logo path resolves correctly from `modules/branding.nix` → `files/plymouth/watermark.png`
- ✅ All 9 source asset files confirmed present in the repository
- ✅ Nix syntax is valid — braces balance, semicolons present, path interpolation correct
- ✅ `pkgs.runCommand` derivation uses correct signature and has `coreutils` available
- ✅ GDM stable-path pattern correctly uses `/etc/vexos/gdm-logo.png`
- ✅ `programs.dconf.profiles.gdm` should merge cleanly with the GNOME module (deferred to build)
- ✅ `system.stateVersion = "25.11"` untouched
- ✅ `hardware-configuration.nix` not committed
- ✅ All three host targets (`vexos-amd`, `vexos-nvidia`, `vexos-vm`) receive the changes

**CRITICAL issues:** None

**Recommended improvements:** 4 non-blocking items (REC-1 through REC-4)

**Build validation:** Deferred to NixOS host — static analysis is clean, no issues expected

---

## Verdict

### ✅ PASS

The implementation is ready for host-side build validation. No refinement cycle is required. Prior to deployment, the team should:
1. Run `nix flake check` and all three `nixos-rebuild dry-build` commands on the NixOS host
2. Visually verify `files/pixmaps/system-logo-white.png` contains vexos artwork (REC-2)
3. Optionally apply REC-1 (`lib.mkDefault` on `boot.plymouth.logo`) for defensive consistency
