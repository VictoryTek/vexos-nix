# Review: dconf-system-level — Move dconf Settings to NixOS System Database

**Reviewer:** Code Review Agent  
**Date:** 2026-03-25  
**Files Reviewed:**
- `modules/desktop.nix`
- `home.nix`
- `.github/docs/subagent_docs/dconf-system-level_spec.md`

---

## Summary of Findings

The implementation is clean, complete, and fully spec-compliant. All dconf settings have been migrated from `home.nix` to the NixOS system-level `programs.dconf.profiles.user.databases` in `modules/desktop.nix`. One low-severity observation is noted regarding the `restart-to` extension UUID reference and stable-vs-unstable channel availability; this does not block approval but should be confirmed at build time on a NixOS host.

---

## 1. Specification Compliance

| Requirement | Status | Notes |
|---|---|---|
| All dconf settings present in `desktop.nix` system database | ✅ PASS | All 9 schema paths match the spec exactly |
| `dconf.settings` fully removed from `home.nix` | ✅ PASS | No `dconf.settings` block remains |
| Function signature `{ config, pkgs, lib, inputs, ... }:` unchanged | ✅ PASS | Exact match |

All 9 dconf key paths are present and populated correctly:
- `org/gnome/shell` — enabled-extensions (12 entries), favorite-apps (8 entries) ✅
- `org/gnome/desktop/interface` — clock-format, cursor-size, cursor-theme, icon-theme ✅
- `org/gnome/desktop/wm/preferences` — button-layout ✅
- `org/gnome/desktop/background` — picture-uri, picture-uri-dark, picture-options ✅
- `org/gnome/shell/extensions/dash-to-dock` — dock-position ✅
- `org/gnome/desktop/screensaver` — lock-enabled, lock-delay ✅
- `org/gnome/session` — idle-delay ✅
- `org/gnome/desktop/app-folders` — folder-children ✅
- `org/gnome/desktop/app-folders/folders/{Games,Office,Utilities,System}` ✅

---

## 2. Correctness

### Extension UUIDs
All 12 extension entries match the authoritative spec list exactly:

| UUID / Reference | Desktop.nix | Spec |
|---|---|---|
| `appindicatorsupport@rgcjonas.gmail.com` | ✅ | ✅ |
| `dash-to-dock@micxgx.gmail.com` | ✅ | ✅ |
| `AlphabeticalAppGrid@stuarthayhurst` | ✅ | ✅ |
| `gamemodeshellextension@trsnaqe.com` | ✅ | ✅ |
| `gnome-ui-tune@itstime.tech` | ✅ | ✅ |
| `nothing-to-say@extensions.gnome.wouter.bolsterl.ee` | ✅ | ✅ |
| `steal-my-focus-window@steal-my-focus-window` | ✅ | ✅ |
| `tailscale-status@maxgallup.github.com` | ✅ | ✅ |
| `caffeine@patapon.info` | ✅ | ✅ |
| `pkgs.gnomeExtensions.restart-to.extensionUuid` | ✅ (not hardcoded) | ✅ |
| `blur-my-shell@aunetx` | ✅ | ✅ |
| `background-logo@fedorahosted.org` | ✅ | ✅ |

### Wallpaper paths
Both `picture-uri` and `picture-uri-dark` use `/home/nimda/Pictures/Wallpapers/...` (hardcoded absolute paths).  
`config.home.homeDirectory` is NOT used. ✅ Matches spec requirement.

### Integer types for lock-delay / idle-delay
- `lock-delay = 0` — plain integer ✅
- `idle-delay = 300` — plain integer ✅  
No `lib.hm.gvariant.mkUint32` wrappers remain. ✅

### App-folder entries
All four folders (Games, Office, Utilities, System) are present with all prescribed `.desktop` entries matching the spec exactly. ✅

---

## 3. Nix Syntax

No syntax errors detected by static inspection:

- All dconf attribute paths are quoted strings (e.g., `"org/gnome/shell"`) ✅
- Lists use space-separated Nix list syntax within `[ ... ]` ✅
- Mixed list types (strings + `pkgs.*` ref) in `enabled-extensions` are valid Nix ✅
- `programs.dconf.profiles.user.databases = [{ ... }];` block is properly opened and closed ✅
- Outer module attrset `{ ... }` closes correctly after the `fonts` and `services.printing` / `hardware.bluetooth` blocks ✅

---

## 4. Module Context

| Requirement | Status |
|---|---|
| `pkgs` in scope (function signature `{ config, pkgs, lib, ... }:`) | ✅ |
| `lib` in scope | ✅ |
| No `lib.hm.gvariant` references anywhere in `desktop.nix` | ✅ |
| `config` in scope (not used in dconf block, but available) | ✅ |

---

## 5. Build Validation

**Result: SKIPPED — nix CLI not available in this Windows/PowerShell environment.**

The following commands were attempted:
```
nix --version
```
Output: `nix not recognized` — command not found.

Build verification must be performed on a NixOS host using:
```bash
nix flake check
sudo nixos-rebuild dry-build --flake .#vexos-amd
sudo nixos-rebuild dry-build --flake .#vexos-nvidia
sudo nixos-rebuild dry-build --flake .#vexos-vm
```

### ⚠️ Low-Severity Observation: `pkgs.gnomeExtensions.restart-to` channel source

The `restart-to` extension is **installed** from `unstable.gnomeExtensions.restart-to` in `environment.systemPackages`, but the dconf UUID is referenced as `pkgs.gnomeExtensions.restart-to.extensionUuid` (stable channel `pkgs`).

This is **spec-compliant** — the spec explicitly instructs use of `pkgs.gnomeExtensions.restart-to.extensionUuid`.

However, if `gnomeExtensions.restart-to` does not exist in the stable nixpkgs-25.05/25.11 channel (only in unstable), the system closure evaluation would fail with an attribute-not-found error. Extension UUIDs are constant strings regardless of version, so a safe alternative would be `pkgs.unstable.gnomeExtensions.restart-to.extensionUuid` — but this is a spec decision, not an implementation error.

**Action required**: Confirm `pkgs.gnomeExtensions.restart-to` evaluates without error during `nix flake check` on a NixOS host. If it fails, change to `pkgs.unstable.gnomeExtensions.restart-to.extensionUuid`.

---

## 6. home.nix Cleanliness

| Check | Status |
|---|---|
| `dconf.settings` block fully removed | ✅ |
| No orphaned closing braces | ✅ |
| `home.stateVersion = "24.05"` present and unchanged | ✅ |
| Function signature `{ config, pkgs, lib, inputs, ... }:` unchanged | ✅ |

The file ends cleanly: GTK theming → wallpapers comment → `home.stateVersion` → closing `}`.

---

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A+ |
| Best Practices | 95% | A |
| Functionality | 95% | A |
| Code Quality | 97% | A+ |
| Security | 100% | A+ |
| Performance | 100% | A+ |
| Consistency | 98% | A+ |
| Build Success | N/A | — |

**Overall Grade: A+ (98%)** *(Build Success excluded from average; pending NixOS host verification)*

---

## Result: PASS ✅

All static checks pass. The implementation is complete, correct, and consistent with the specification. Build validation must be confirmed on a NixOS host before the change is considered fully production-ready.

### Pre-push checklist
- [ ] Run `nix flake check` on a NixOS host — confirm clean evaluation
- [ ] Confirm `pkgs.gnomeExtensions.restart-to.extensionUuid` evaluates (stable channel has the attribute)
- [ ] Run `sudo nixos-rebuild dry-build --flake .#vexos-amd` (and nvidia/vm variants) — confirm no closure errors
- [ ] Verify `hardware-configuration.nix` is NOT committed to the repository
- [ ] Confirm `system.stateVersion` is unchanged in `configuration.nix`
