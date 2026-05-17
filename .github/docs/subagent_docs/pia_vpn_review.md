# PIA VPN — Review & Quality Assurance

**Feature:** `pia_vpn`  
**Reviewer:** QA Subagent  
**Date:** 2026-05-17  
**Status:** NEEDS_REFINEMENT  

---

## 1. Files Reviewed

| File | Status |
|------|--------|
| `modules/pia.nix` | Reviewed |
| `configuration-stateless.nix` | Reviewed |
| `configuration-desktop.nix` | Reviewed |
| `configuration-htpc.nix` | Reviewed |
| `configuration-server.nix` | Reviewed (confirmed no PIA import) |
| `configuration-headless-server.nix` | Reviewed (confirmed no PIA import) |
| `justfile` (lines 1611–1682) | Reviewed |

---

## 2. Validation Checklist

### 2.1 iproute2 path in `modules/pia.nix`

**Result: ✅ PASS**

```nix
environment.etc."iproute2/rt_tables".source =
    "${pkgs.iproute2}/share/iproute2/rt_tables";
```

Uses `share/iproute2/rt_tables` — the correct path in the nixpkgs iproute2 package. The spec
§1.2 identified a critical bug where the initial implementation used `lib/iproute2/rt_tables`
(which doesn't exist in the Nix store). The implementation has been corrected to `share/`.

---

### 2.2 `vexos.impermanence.extraPersistDirs` present

**Result: ✅ Present — ❌ Causes build failure on desktop/htpc**

The line is present at `modules/pia.nix:46`:
```nix
vexos.impermanence.extraPersistDirs = [ "/opt/piavpn" ];
```

However, the `vexos.impermanence` NixOS option is **only defined when `modules/impermanence.nix`
is imported**. `configuration-desktop.nix` and `configuration-htpc.nix` do NOT import
`modules/impermanence.nix`. Evaluating these configurations produces:

```
error: The option `vexos.impermanence' does not exist. Definition values:
- In `.../modules/pia.nix':
    {
      extraPersistDirs = [
        "/opt/piavpn"
      ];
    }
```

This is a **CRITICAL BUILD FAILURE** for desktop and htpc configurations.  
See §4 (Build Results) for details.

---

### 2.3 No `lib.mkIf` guards in `modules/pia.nix`

**Result: ✅ PASS**

No `lib.mkIf` expressions appear anywhere in `modules/pia.nix`. The module is unconditional.

---

### 2.4 Server and headless-server do NOT import `./modules/pia.nix`

**Result: ✅ PASS**

`configuration-server.nix` imports list:
- Checked — `./modules/pia.nix` is absent ✓

`configuration-headless-server.nix` imports list:
- Checked — `./modules/pia.nix` is absent ✓

---

### 2.5 Stateless, desktop, htpc DO import `./modules/pia.nix`

**Result: ✅ PASS (imports present, builds broken — tracked under §2.2)**

| Configuration | Imports `./modules/pia.nix` |
|---------------|----------------------------|
| `configuration-stateless.nix` | ✅ Yes (line 23) |
| `configuration-desktop.nix` | ✅ Yes (line 31) |
| `configuration-htpc.nix` | ✅ Yes (line 22) |

---

### 2.6 All 15 justfile PIA recipes present

**Result: ✅ PASS**

| Recipe | Line | Found |
|--------|------|-------|
| `pia-install [VERSION]` | 1614 | ✅ |
| `pia-uninstall` | 1630 | ✅ |
| `pia-update` | 1634 | ✅ |
| `pia-status` | 1639 | ✅ |
| `pia-connect [REGION]` | 1646 | ✅ |
| `pia-disconnect` | 1654 | ✅ |
| `pia-regions` | 1658 | ✅ |
| `pia-kill-switch-on` | 1662 | ✅ |
| `pia-kill-switch-off` | 1666 | ✅ |
| `pia-port-forward-on` | 1670 | ✅ |
| `pia-port-forward-off` | 1674 | ✅ |
| `pia-background-on` | 1678 | ✅ |
| `pia-gui` | 1682 | ✅ |
| `pia-logs` | 1686 | ✅ |
| `pia-version` | 1690 | ✅ |

All 15 recipes are present with correct implementations.

---

### 2.7 `hardware-configuration.nix` NOT in repository

**Result: ✅ PASS**

`find . -name "hardware-configuration.nix"` returns no results.  
`git ls-files | grep hardware` returns only documentation files in `.github/docs/`.  
No hardware configuration is tracked in the repository.

---

### 2.8 `system.stateVersion` not changed

**Result: ✅ PASS**

All configuration files report `system.stateVersion = "25.11"`:

| File | stateVersion |
|------|-------------|
| `configuration-desktop.nix:52` | `"25.11"` |
| `configuration-stateless.nix:78` | `"25.11"` |
| `configuration-htpc.nix:31` | `"25.11"` |
| `configuration-server.nix:38` | `"25.11"` |
| `configuration-headless-server.nix:54` | `"25.11"` |
| `configuration-vanilla.nix:28` | `"25.11"` |

---

## 3. Module Architecture Audit

### 3.1 Module structure assessment

`modules/pia.nix` correctly follows the Option B pattern with **one exception** — the
`vexos.impermanence.extraPersistDirs` assignment (§2.2):

| Rule | Status |
|------|--------|
| No `lib.mkIf` guards in base module | ✅ Compliant |
| Settings in the base file apply to ALL importing roles | ❌ **VIOLATION** — `vexos.impermanence.extraPersistDirs` only works in roles that also import `modules/impermanence.nix` |
| Role specificity expressed by selective imports | ✅ Correct approach (but stateless-specific line is in the shared module) |

### 3.2 nix-ld library list

The `programs.nix-ld.libraries` list is complete and matches the spec §4 cross-reference exactly.
All 21 libraries are present including `xorg.libXi` (XInput2) which was flagged as a required
addition in the spec.

### 3.3 Kernel modules

Implementation uses `boot.kernelModules = [ "wireguard" "tun" ]`.  
The spec §5 proposes `[ "wireguard" ]` only, but §1.2 explicitly notes the `tun` addition as
intentional and correct (OpenVPN compatibility). This is not a defect.

### 3.4 Wrapper script LD_LIBRARY_PATH syntax

Implementation uses `''${LD_LIBRARY_PATH}` (simpler form).  
The spec §5 proposes `''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}` (parameter expansion with
separator guard, which avoids a trailing `:` when `LD_LIBRARY_PATH` is unset).  
The simpler form still prepends correctly but may produce a trailing `:` in the library path
when `LD_LIBRARY_PATH` is not previously set. This is a MINOR issue — most loaders tolerate
trailing `:` in `LD_LIBRARY_PATH`. It will not cause a runtime failure, but the parameter
expansion form is cleaner.

---

## 4. Build Validation Results

### Environment note

`sudo nixos-rebuild dry-build` could not be executed (container environment: no-new-privileges).  
Equivalent evaluation was performed using `nix eval --impure .#nixosConfigurations.<name>.config.system.build.toplevel.drvPath`.

### 4.1 `nix flake check --no-build`

**Result: ❌ FAIL (pre-existing, unrelated to PIA)**

```
error: access to absolute path '/etc' is forbidden in pure evaluation mode
```

**Pre-existing:** confirmed by running `nix flake check --no-build` after `git stash` (removing
all PIA changes). The error exists on the base branch without any PIA modifications. This failure
is caused by host configurations importing `hardware-configuration.nix` from `/etc/nixos/`, which
is a design constraint of this repository. It is NOT caused by the PIA changes.

### 4.2 `nix eval --impure .#nixosConfigurations.vexos-stateless-amd`

**Result: ✅ PASS**

```
"/nix/store/ldmpwyfbnyhm9sv7kfnpm3sjdx30iljp-nixos-system-vexos-25.11.drv"
```

The stateless-amd configuration evaluates successfully. `modules/impermanence.nix` is imported
in `configuration-stateless.nix`, so the `vexos.impermanence` option exists and
`extraPersistDirs = [ "/opt/piavpn" ]` is accepted.

### 4.3 `nix eval --impure .#nixosConfigurations.vexos-desktop-amd`

**Result: ❌ FAIL — CRITICAL**

```
error: The option `vexos.impermanence' does not exist.
- In `.../modules/pia.nix': { extraPersistDirs = [ "/opt/piavpn" ]; }
```

`configuration-desktop.nix` does not import `modules/impermanence.nix`. Setting
`vexos.impermanence.extraPersistDirs` fails with option-not-found error.

### 4.4 `nix eval --impure .#nixosConfigurations.vexos-desktop-nvidia`

**Result: ❌ FAIL — CRITICAL**

Same error as 4.3.

### 4.5 `nix eval --impure .#nixosConfigurations.vexos-desktop-vm`

**Result: ❌ FAIL — CRITICAL**

Same error as 4.3.

### 4.6 `nix eval --impure .#nixosConfigurations.vexos-htpc-amd`

**Result: ❌ FAIL — CRITICAL**

Same error as 4.3. `configuration-htpc.nix` does not import `modules/impermanence.nix`.

---

## 5. Issues Found

### CRITICAL — `vexos.impermanence.extraPersistDirs` in shared module causes desktop/htpc build failure

**Severity:** CRITICAL  
**Affects:** All desktop variants (amd, nvidia, nvidia-legacy535, nvidia-legacy470, intel, vm) + all htpc variants  
**Root Cause:** `modules/pia.nix` unconditionally sets `vexos.impermanence.extraPersistDirs`, but the `vexos.impermanence` NixOS option is only declared inside `modules/impermanence.nix`. Desktop and htpc configurations do not import `modules/impermanence.nix`, so the option does not exist in those evaluation contexts.  
**Architecture Analysis:** This is an architecture violation. Content in `modules/pia.nix` (a shared base module) must apply unconditionally to ALL roles that import it. Setting a stateless-only option in the shared module breaks the other roles.

**Required Fix (Phase 4):**

Per the architecture rules (Option B pattern):
> "When adding new content that only applies to some roles: create a new `modules/<subsystem>-<qualifier>.nix` file; do NOT add a `lib.mkIf` guard to an existing shared file."

1. **Remove** `vexos.impermanence.extraPersistDirs = [ "/opt/piavpn" ];` from `modules/pia.nix`
2. **Create** `modules/pia-stateless.nix` containing only:
   ```nix
   { ... }:
   {
     # Persist PIA installation across reboots on tmpfs-rooted (stateless) systems.
     # /opt/piavpn would be wiped on each reboot without this entry.
     vexos.impermanence.extraPersistDirs = [ "/opt/piavpn" ];
   }
   ```
3. **Add** `./modules/pia-stateless.nix` to the imports in `configuration-stateless.nix`
4. **Do NOT** add `pia-stateless.nix` to desktop/htpc imports

This preserves:
- `modules/pia.nix` remains unconditional (works in all three roles)
- `/opt/piavpn` is persisted in stateless (the role that needs it)
- Desktop and htpc build successfully

### MINOR — Wrapper `LD_LIBRARY_PATH` missing separator guard

**Severity:** MINOR (cosmetic, no runtime failure)  
**Location:** `modules/pia.nix` wrapper scripts  
**Current:**
```bash
export LD_LIBRARY_PATH=/opt/piavpn/lib:${LD_LIBRARY_PATH}
```
**Better:**
```bash
export LD_LIBRARY_PATH=/opt/piavpn/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
```
The current form appends a trailing `:` when `LD_LIBRARY_PATH` is unset (evaluates as
`/opt/piavpn/lib:`). The `${VAR:+:$VAR}` form avoids the trailing separator. Most dynamic
linkers treat a trailing `:` as a reference to the current directory, which is a
subtle security concern. This is recommended for fix during Phase 4.

---

## 6. Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 82% | B |
| Best Practices | 75% | C+ |
| Functionality | 55% | F |
| Code Quality | 85% | B |
| Security | 78% | C+ |
| Performance | 95% | A |
| Consistency | 85% | B |
| Build Success | 25% | F |

> **Functionality** and **Build Success** are low because desktop and htpc closures fail to
> evaluate. Stateless evaluates correctly (1 of 3 imported roles works = ~33%; partial credit
> for correct stateless behavior and all-correct justfile = 55% final). Build success is 25%
> because 1 of 4 tested configurations passes (stateless-amd only).

**Overall Grade: D+ (72.5%) — NEEDS_REFINEMENT**

---

## 7. Return

### Build results summary

| Command | Result |
|---------|--------|
| `nix flake check --no-build` | ❌ FAIL (pre-existing, unrelated to PIA — `/etc` pure eval) |
| `nix eval vexos-stateless-amd` | ✅ PASS |
| `nix eval vexos-desktop-amd` | ❌ FAIL — `vexos.impermanence` option not found |
| `nix eval vexos-desktop-nvidia` | ❌ FAIL — `vexos.impermanence` option not found |
| `nix eval vexos-desktop-vm` | ❌ FAIL — `vexos.impermanence` option not found |
| `nix eval vexos-htpc-amd` | ❌ FAIL — `vexos.impermanence` option not found |

### Verdict: **NEEDS_REFINEMENT**

**Critical issue (must fix before approval):**

`modules/pia.nix` sets `vexos.impermanence.extraPersistDirs` unconditionally, but this option
only exists in configurations that also import `modules/impermanence.nix`. Desktop and htpc
don't import impermanence — so all desktop and htpc closures fail to evaluate.

**Fix:** Extract the `extraPersistDirs` line into `modules/pia-stateless.nix` and import that
file only in `configuration-stateless.nix`.

**Recommended improvement (Phase 4):**

Fix the `LD_LIBRARY_PATH` trailing-colon issue in the wrapper scripts using the
`${VAR:+:$VAR}` parameter expansion pattern.
