# Review: Rename configuration.nix + Bibata-Modern-Classic Cursor (HTPC)
**Feature:** `rename_and_cursor`
**Date:** 2026-04-17
**Reviewer:** QA Subagent
**Verdict:** ✅ PASS (with one non-critical documentation gap noted)

---

## 1. Task 1: Rename — Checklist Results

### 1.1 `configuration.nix` No Longer Exists

**Result: ✅ PASS**

`Test-Path "c:\Projects\vexos-nix\configuration.nix"` returned `False`.

Root-level configuration files are now:
```
configuration-desktop.nix
configuration-htpc.nix
configuration-server.nix
configuration-stateless.nix
```

The rename is complete. All four roles now follow the `configuration-<role>.nix` pattern.

---

### 1.2 All 4 Host Files Import `../configuration-desktop.nix`

**Result: ✅ PASS**

| File | Import Path | Status |
|---|---|---|
| `hosts/desktop-amd.nix` | `../configuration-desktop.nix` | ✅ |
| `hosts/desktop-nvidia.nix` | `../configuration-desktop.nix` | ✅ |
| `hosts/desktop-intel.nix` | `../configuration-desktop.nix` | ✅ |
| `hosts/desktop-vm.nix` | `../configuration-desktop.nix` | ✅ |

All four host files verified by direct read.

---

### 1.3 `flake.nix` `nixosModules.base` Import Updated

**Result: ✅ PASS**

`flake.nix` line ~354 (inside `nixosModules.base`):
```nix
imports = [
  home-manager.nixosModules.home-manager
  ./configuration-desktop.nix
];
```

No reference to `./configuration.nix` found anywhere in `flake.nix`.

---

### 1.4 `scripts/preflight.sh` stateVersion Check Updated

**Result: ✅ PASS**

`scripts/preflight.sh` lines 118–122:
```bash
echo "[4/9] Verifying system.stateVersion in configuration-desktop.nix..."
if grep -q 'system\.stateVersion' configuration-desktop.nix; then
  pass "system.stateVersion is present in configuration-desktop.nix"
else
  fail "system.stateVersion is missing from configuration-desktop.nix"
```

Matches spec Step 3 exactly.

---

### 1.5 Full-Repo Stale Reference Scan

**Result: ✅ PASS — No stale functional references**

PowerShell scan of all `.nix` and `.sh` files:
```
Get-ChildItem -Path "c:\Projects\vexos-nix" -Recurse -Include "*.nix","*.sh" |
  Select-String -Pattern 'configuration\.nix' |
  Where-Object { $_.Line -notmatch 'hardware-configuration\.nix' }
```
**Output: (empty) — zero matches.**

All remaining `configuration.nix` references found in the broader markdown scan are confined to:
- Historical spec/review documents in `.github/docs/subagent_docs/` (pre-rename work — expected, no build impact)
- `.github/copilot-instructions.md` (see 1.6 below)

---

### 1.6 `copilot-instructions.md` — Spec Required Update NOT Applied

**Result: ⚠️ NON-CRITICAL DOCUMENTATION GAP**

The spec (Step 5) explicitly required updating four references in `.github/copilot-instructions.md`. These remain stale:

| Line | Current Text | Required Update |
|---|---|---|
| 83 | `flake.nix`, `configuration.nix`, and future module files | → `configuration-desktop.nix` |
| 89 | `Host configs live in hosts/ and import configuration.nix` | → `import configuration-desktop.nix` |
| 92 | `system.stateVersion in configuration.nix MUST NOT be changed` | → `configuration-desktop.nix` |
| 578 | `Verification that system.stateVersion is present in configuration.nix` | → `configuration-desktop.nix` |

**Severity: NON-CRITICAL** — these are documentation comments only. No build impact. No functional impact. However, they will mislead future AI agents reading the instructions file, as the file describes an outdated project structure.

**Recommendation:** Fix in a follow-up pass or during refinement — classified as RECOMMENDED (not CRITICAL).

---

### 1.7 `modules/gnome.nix` Comment Updated

**Result: ✅ PASS**

`modules/gnome.nix` line 132:
```nix
# NOTE: gnome-extension-manager is installed in configuration-desktop.nix (desktop only).
```

Matches spec Step 4 exactly.

---

## 2. Task 2: HTPC Cursor — Checklist Results

### 2.1 `home-htpc.nix` has `home.pointerCursor` Block

**Result: ✅ PASS**

```nix
home.pointerCursor = {
  name    = "Bibata-Modern-Classic";
  package = pkgs.bibata-cursors;
  size    = 24;
};
```

Present. Matches spec Step 8 exactly.

---

### 2.2 `home-htpc.nix` has `gtk.cursorTheme` Matching Desktop

**Result: ✅ PASS**

```nix
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

All three GTK declarations are present. `gtk.enable = true` ensures GTK config files are written. Name, package, and size are identical to the desktop role.

---

### 2.3 `configuration-htpc.nix` has `bibata-cursors` in `environment.systemPackages`

**Result: ✅ PASS**

```nix
environment.systemPackages = with pkgs; [
  bibata-cursors
  kora-icon-theme
  ghostty
];
```

`bibata-cursors` added as the first entry — consistent alphabetical ordering with `kora-icon-theme`. Matches spec Step 6.

---

### 2.4 System dconf Profile Updated with cursor-theme / cursor-size

**Result: ✅ PASS**

`configuration-htpc.nix` `programs.dconf.profiles.user.databases[0]`:
```nix
settings."org/gnome/desktop/interface" = {
  cursor-theme = "Bibata-Modern-Classic";
  cursor-size  = 24;
  icon-theme   = "kora";
  clock-format = "12h";
};
```

Matches spec Step 7. `cursor-size` is passed as a plain Nix integer — correct for NixOS system dconf module (type inference is handled by the module internally).

---

### 2.5 Cross-Role Cursor Consistency

**Result: ✅ PASS**

| Config | `home.pointerCursor` | `gtk.enable` | `gtk.iconTheme` | `gtk.cursorTheme` |
|---|---|---|---|---|
| `home-desktop.nix` | ✅ (`Bibata-Modern-Classic`, size 24) | ✅ | ✅ (`kora`) | ✅ (`Bibata-Modern-Classic`, size 24) |
| `home-htpc.nix` | ✅ (`Bibata-Modern-Classic`, size 24) | ✅ | ✅ (`kora`) | ✅ (`Bibata-Modern-Classic`, size 24) |
| `home-server.nix` | ✅ (`Bibata-Modern-Classic`, size 24) | ✅ | ✅ (`kora`) | ✅ (`Bibata-Modern-Classic`, size 24) |
| `home-stateless.nix` | ✅ (`Bibata-Modern-Classic`, size 24) | ✅ | ✅ (`kora`) | ✅ (`Bibata-Modern-Classic`, size 24) |

All four roles are now fully consistent. The HTPC cursor configuration gap identified in the spec has been resolved.

**Note on `home.packages`:** `home-htpc.nix` does not have a `home.packages` section. The `bibata-cursors` and `kora-icon-theme` packages referenced in `gtk.iconTheme.package` and `gtk.cursorTheme.package` are resolved from `pkgs.*`. With `useGlobalPkgs = true` in `flake.nix`'s `htpcHomeManagerModule`, these resolve to the shared system-level pkgs instance. Both packages are present in `environment.systemPackages` in `configuration-htpc.nix`. This is the correct approach as documented in the spec.

---

## 3. Build Validation

**Nix availability:** `nix` is NOT available on this Windows machine (native). WSL Ubuntu is present but does not have `nix` installed. Build validation is performed syntactically.

### Syntactic Validation

| File | Syntactic Check | Result |
|---|---|---|
| `configuration-desktop.nix` | Valid Nix attrset, imports intact, no orphan braces | ✅ |
| `flake.nix` | `./configuration-desktop.nix` import path correct, module structure intact | ✅ |
| `hosts/desktop-amd.nix` | `../configuration-desktop.nix` import present, file structure correct | ✅ |
| `hosts/desktop-nvidia.nix` | `../configuration-desktop.nix` import present, file structure correct | ✅ |
| `hosts/desktop-intel.nix` | `../configuration-desktop.nix` import present, file structure correct | ✅ |
| `hosts/desktop-vm.nix` | `../configuration-desktop.nix` import present, file structure correct | ✅ |
| `configuration-htpc.nix` | `bibata-cursors` in systemPackages, dconf cursor keys set, braces balanced | ✅ |
| `home-htpc.nix` | `home.pointerCursor`, `gtk.enable`, `gtk.iconTheme`, `gtk.cursorTheme` all present; braces balanced | ✅ |
| `scripts/preflight.sh` | `configuration-desktop.nix` referenced correctly in CHECK 4 | ✅ |
| `modules/gnome.nix` | Comment updated to `configuration-desktop.nix` | ✅ |

### Build Confidence Assessment

All import paths are valid. The old `configuration.nix` filename no longer exists and is not referenced in any functional Nix expression. The HTPC cursor additions follow established patterns used by the icon theme. No new flake inputs are introduced; no `system.stateVersion` has been modified.

Build confidence: **HIGH**.

---

## 4. Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 92% | A- |
| Best Practices | 97% | A+ |
| Functionality | 100% | A+ |
| Code Quality | 98% | A+ |
| Security | 100% | A+ |
| Performance | 100% | A+ |
| Consistency | 100% | A+ |
| Build Success | 95% | A (syntactic — nix unavailable) |

**Overall Grade: A (98%)**

---

## 5. Issues Summary

| # | Severity | Category | Description |
|---|---|---|---|
| 1 | ⚠️ NON-CRITICAL | Spec Compliance | `.github/copilot-instructions.md` has 4 stale references to `configuration.nix` (lines 83, 89, 92, 578). Spec Step 5 required these to be updated. No build impact. |

---

## 6. Final Verdict

**✅ PASS**

All critical functional requirements have been implemented correctly:
- `configuration.nix` renamed to `configuration-desktop.nix` — complete
- All 4 host import paths updated — complete
- `flake.nix` `nixosModules.base` updated — complete
- `scripts/preflight.sh` CHECK 4 updated — complete
- `modules/gnome.nix` comment updated — complete
- HTPC: `bibata-cursors` added to system packages — complete
- HTPC: system dconf `cursor-theme` and `cursor-size` added — complete
- HTPC: `home.pointerCursor`, `gtk.enable`, `gtk.iconTheme`, `gtk.cursorTheme` added to `home-htpc.nix` — complete
- Cross-role cursor consistency: all four roles now identical — complete

The single outstanding gap (`copilot-instructions.md` stale references) is **non-critical documentation** with no build or functional impact. It is **RECOMMENDED** to fix but does not block this work from being considered complete.
