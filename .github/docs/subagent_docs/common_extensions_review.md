# Review: `commonExtensions` GNOME Shell Extension Deduplication

**Feature:** `common_extensions`
**Review date:** 2026-05-15
**Reviewer:** QA subagent (Phase 3)
**Verdict:** **NEEDS_REFINEMENT**

---

## 1. Specification Compliance

### ✅ Passing checks

| Check | Result |
|-------|--------|
| `options.vexos.gnome.commonExtensions` declared in `gnome.nix` | ✅ Present |
| Type is `lib.types.listOf lib.types.str` | ✅ Correct |
| `internal = true` set | ✅ Correct |
| `description` field present | ✅ Correct |
| 12-entry canonical default list present | ✅ All 12 UUIDs intact, byte-for-byte match with spec |
| `let commonExtensions = …` removed from all four role files | ✅ Not found in any role file |
| `gnome-desktop.nix` uses `config.vexos.gnome.commonExtensions ++ [ "gamemodeshellextension@trsnaqe.com" ]` | ✅ Correct |
| `gnome-htpc.nix` uses `config.vexos.gnome.commonExtensions` directly | ✅ Correct |
| `gnome-server.nix` uses `config.vexos.gnome.commonExtensions` directly | ✅ Correct |
| `gnome-stateless.nix` uses `config.vexos.gnome.commonExtensions` directly | ✅ Correct |
| No `lib.mkIf` guards added to `gnome.nix` | ✅ None introduced |
| Extension UUID strings preserved exactly (order and content) | ✅ Identical |
| `hardware-configuration.nix` NOT tracked in git | ✅ Confirmed (`git ls-files` returns nothing) |
| `system.stateVersion` not changed | ✅ Still `"25.11"` |

### ❌ Failing check

| Check | Result |
|-------|--------|
| NixOS module structure is valid after `options` declaration added | ❌ **CRITICAL — see Section 2** |

---

## 2. Critical Build Failure

### Error

```
error: Module `.../modules/gnome.nix' has an unsupported attribute `environment'.
This is caused by introducing a top-level `config' or `options' attribute.
Add configuration attributes immediately on the top level instead, or move
all of them (namely: environment fonts hardware nixpkgs programs services xdg)
into the explicit `config' attribute.
```

**Root cause:** NixOS module system rule: when a module file declares **any** `options.*`
attribute at the top level, NixOS treats the file as using the "explicit split" form and
requires that **all configuration attributes** be placed inside a `config = { … };` block.

Before this change `gnome.nix` had no `options` declaration, so NixOS accepted all
top-level attributes as config. After adding `options.vexos.gnome.commonExtensions`,
every existing top-level config attribute (`nixpkgs`, `services`, `programs`,
`environment`, `fonts`, `hardware`, `xdg`) became structurally invalid.

**All four GNOME roles fail at evaluation time.**

`nix flake check --impure` exits non-zero. Dry-build commands were not attempted
because the error occurs during flake evaluation before any build.

### Required fix

In `modules/gnome.nix`, keep `options.vexos.gnome.commonExtensions = lib.mkOption { … }` at
the top level and wrap **all existing configuration attributes** in an explicit
`config = { … };` block:

```nix
{ config, pkgs, lib, ... }:
{
  imports = [ ./gnome-flatpak-install.nix ];

  options.vexos.gnome.commonExtensions = lib.mkOption {
    type        = lib.types.listOf lib.types.str;
    default     = [ … ];
    internal    = true;
    description = "…";
  };

  config = {
    nixpkgs.overlays = [ … ];
    services.xserver.enable = …;
    # … all remaining config …
  };
}
```

No changes are needed to the four role files; they are correctly implemented.

---

## 3. Build Validation Results

| Variant | Step | Result |
|---------|------|--------|
| `nix flake check --impure` | Evaluation | ❌ FAIL — evaluation error in `gnome.nix` |
| `vexos-desktop-amd` dry-build | Not attempted | ❌ Blocked by evaluation error |
| `vexos-htpc-amd` dry-build | Not attempted | ❌ Blocked by evaluation error |
| `vexos-server-amd` dry-build | Not attempted | ❌ Blocked by evaluation error |
| `vexos-stateless-amd` dry-build | Not attempted | ❌ Blocked by evaluation error |

---

## 4. Detailed Findings

### 4.1 `modules/gnome.nix`

- **CRITICAL:** `options` declared at top level but all configuration
  attributes remain at the top level instead of inside a `config = { };`
  block. This violates the NixOS module system's structural constraint.
- The option declaration itself (`type`, `default`, `internal`, `description`)
  is correct and complete.
- No `lib.mkIf` guards were added — Option B compliance is maintained.

### 4.2 `modules/gnome-desktop.nix`

- ✅ `let commonExtensions` binding removed.
- ✅ `enabled-extensions = config.vexos.gnome.commonExtensions ++ [ "gamemodeshellextension@trsnaqe.com" ]` — correct.
- ✅ `imports = [ ./gnome.nix ]` present.
- No structural issues.

### 4.3 `modules/gnome-htpc.nix`

- ✅ `let commonExtensions` binding removed.
- ✅ `enabled-extensions = config.vexos.gnome.commonExtensions` — correct.
- No structural issues.

### 4.4 `modules/gnome-server.nix`

- ✅ `let commonExtensions` binding removed.
- ✅ `enabled-extensions = config.vexos.gnome.commonExtensions` — correct.
- No structural issues.

### 4.5 `modules/gnome-stateless.nix`

- ✅ `let commonExtensions` binding removed.
- ✅ `enabled-extensions = config.vexos.gnome.commonExtensions` — correct.
- No structural issues.

---

## 5. Score Table

| Category | Score | Grade |
|---|---|---|
| Specification Compliance | 92% | A |
| Best Practices | 70% | C |
| Functionality | 0% | F |
| Code Quality | 85% | B |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 95% | A |
| Build Success | 0% | F |

**Overall Grade: F (68%)**

> Functionality and Build Success are scored 0 because the configuration fails
> evaluation — no build of any GNOME role completes. All other categories
> reflect the implementation quality of the changes that *were* made correctly.

---

## 6. Summary

The implementation is **logically correct**: the option is well-declared, the
canonical list is intact, the role files correctly consume the option, and all
four `let commonExtensions` duplicates have been removed. However, the
implementation introduced one structural NixOS module error: adding an `options`
declaration to `gnome.nix` without wrapping the existing config attributes in a
`config = { }` block. This causes a hard evaluation failure across all 34 flake
outputs that import any GNOME role.

The fix is **contained to `modules/gnome.nix`** only — a single-file change
that wraps the body of the file in `config = { … }`.

---

## 7. Required Actions for Refinement

### CRITICAL (must fix before PASS)

1. **`modules/gnome.nix`** — wrap all configuration attributes in `config = { … }`:
   - `nixpkgs.overlays`
   - `services.xserver.*`
   - `services.desktopManager.*`
   - `programs.dconf.*`
   - `services.displayManager.*`
   - `xdg.portal.*`
   - `environment.sessionVariables`
   - `environment.gnome.excludePackages`
   - `environment.systemPackages`
   - `fonts.*`
   - `services.printing.*`
   - `hardware.bluetooth.*`
   - `services.blueman.*`

   Keep `options.vexos.gnome.commonExtensions` at the top level (outside `config`).

### No changes required

- `modules/gnome-desktop.nix` — correct as implemented
- `modules/gnome-htpc.nix` — correct as implemented
- `modules/gnome-server.nix` — correct as implemented
- `modules/gnome-stateless.nix` — correct as implemented
