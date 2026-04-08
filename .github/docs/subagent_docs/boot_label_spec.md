# Boot Label Specification — vexos-nix

**Feature:** Clean systemd-boot menu labels per host variant  
**Date:** 2026-04-08  
**Phase:** 1 — Research & Specification

---

## Current State Analysis

### Boot Entry Format
NixOS systemd-boot entries are rendered as:

```
{distroName} (Generation {N} {label} ({kernelVersion}), built on {date})
```

### Current Output
```
VexOS (Generation 1 NixOS Warbler 25.05.813798.40ee5e1944be (Linux 6.12.63), built on 2026-04-07)
```

### Root Cause
- `modules/branding.nix` sets `system.nixos.distroName = "VexOS"` — plain assignment, no `lib.mkDefault`, so no host-level override is possible without a merge conflict.
- `system.nixos.label` is unset across the entire repository. NixOS defaults this to the full auto-generated string `NixOS Warbler 25.05.813798.40ee5e1944be`, which is verbose and includes commit hashes irrelevant to end users.
- There are four host variants (`amd`, `nvidia`, `intel`, `vm`) but all currently share the same undifferentiated label "VexOS".

### Affected Files
| File | Current Relevant Content |
|------|--------------------------|
| `modules/branding.nix` | `system.nixos.distroName = "VexOS";` — no label set |
| `hosts/amd.nix` | No distroName override |
| `hosts/nvidia.nix` | No distroName override |
| `hosts/intel.nix` | No distroName override |
| `hosts/vm.nix` | No distroName override |

---

## Problem Definition

1. **No host differentiation:** All four host variants show "VexOS" in the boot menu, making it impossible to distinguish which configuration was booted at a glance.
2. **Verbose auto-generated label:** The default `system.nixos.label` includes the full nixpkgs commit hash and codename, producing a cluttered and uninformative boot entry string.
3. **Non-overridable distroName:** The plain assignment in `modules/branding.nix` uses NixOS module priority 100, preventing host configs from setting a different value without a conflict error.

---

## Proposed Solution Architecture

### NixOS Option Reference

| Option | Type | Priority Behavior |
|--------|------|-------------------|
| `system.nixos.distroName` | `string` | Plain assignment = priority 100. `lib.mkDefault` = priority 1000 (lower wins = overridable by plain assignment). |
| `system.nixos.label` | `strMatching "[a-zA-Z0-9_./-]+"` | Plain assignment. Controls the version string shown in boot entries. |

### Strategy

1. **Make `distroName` overridable** in `modules/branding.nix` by wrapping it with `lib.mkDefault`. This sets the fallback to "VexOS" at priority 1000, allowing any host file to override it with a plain assignment at priority 100.

2. **Set a clean `label`** in `modules/branding.nix` so all hosts share a consistent short version string ("25.11") instead of the auto-generated hash.

3. **Add per-host `distroName` overrides** in each `hosts/*.nix` so each variant is clearly identified in the boot menu.

### Target Boot Entries

| Host | Boot Entry |
|------|------------|
| `vexos-desktop-amd` | `VexOS AMD (Generation 1 25.11 (Linux 6.12.63), built on 2026-04-07)` |
| `vexos-desktop-nvidia` | `VexOS NVIDIA (Generation 1 25.11 (Linux 6.12.63), built on 2026-04-07)` |
| `vexos-desktop-intel` | `VexOS Intel (Generation 1 25.11 (Linux 6.12.63), built on 2026-04-07)` |
| `vexos-desktop-vm` | `VexOS VM (Generation 1 25.11 (Linux 6.12.63), built on 2026-04-07)` |

---

## Implementation Steps

### Step 1 — `modules/branding.nix`

**Change 1:** Wrap `distroName` with `lib.mkDefault` to allow host overrides.

```nix
# Before
system.nixos.distroName = "VexOS";

# After
system.nixos.distroName = lib.mkDefault "VexOS";
```

**Change 2:** Add `system.nixos.label` to replace the auto-generated hash string.

```nix
system.nixos.label = "25.11";
```

> Ensure `lib` is available in the module arguments. If the module header is `{ config, pkgs, ... }`, update it to `{ config, lib, pkgs, ... }` (or confirm `lib` is already present).

### Step 2 — `hosts/amd.nix`

Add inside the `config` (or top-level options) block:

```nix
system.nixos.distroName = "VexOS AMD";
```

### Step 3 — `hosts/nvidia.nix`

Add inside the `config` (or top-level options) block:

```nix
system.nixos.distroName = "VexOS NVIDIA";
```

### Step 4 — `hosts/intel.nix`

Add inside the `config` (or top-level options) block:

```nix
system.nixos.distroName = "VexOS Intel";
```

### Step 5 — `hosts/vm.nix`

Add inside the `config` (or top-level options) block:

```nix
system.nixos.distroName = "VexOS VM";
```

---

## Dependencies

No new external dependencies, flake inputs, or packages are required. All changes use built-in NixOS module options.

---

## Risks and Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| `system.nixos.label` type constraint rejects the value | Medium | The type is `strMatching "[a-zA-Z0-9_./-]+"`. The value `"25.11"` contains only digits and a dot, both in the allowed set. This is valid. |
| `lib` not imported in `modules/branding.nix` | Low | Implementer must verify the module's argument list includes `lib`. If not present, add it. |
| Host file uses `config = { ... }` vs flat attribute style | Low | Implementer must inspect the actual structure of each `hosts/*.nix` and place `system.nixos.distroName` in the correct scope. |
| `system.nixos.label` affects `/etc/os-release` `VERSION_ID` | Low | This is acceptable; the label is intentional branding, not a nixpkgs version pin. |
| Merge conflict if another module also sets `distroName` without `mkDefault` | Low | Grep the repository before finalising. Currently no other module sets this option. |
| `nix flake check` evaluation failure due to syntax error | Medium | Implementer must run `nix flake check` after changes and fix any parse errors before marking implementation complete. |

---

## Validation Criteria

The implementation is complete when:

1. `nix flake check` exits with code 0.
2. `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd` succeeds.
3. `sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia` succeeds.
4. `sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm` succeeds.
5. The generated `/etc/os-release` on each host contains the expected `NAME=` value.
6. systemd-boot entries on each host reflect the per-host `distroName` and the short `"25.11"` label.
