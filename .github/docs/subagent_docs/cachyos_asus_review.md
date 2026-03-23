# Review: CachyOS Kernel + ASUS Hardware Support
**Feature**: `cachyos_asus`  
**Phase**: 3 — Review & Quality Assurance  
**Date**: 2026-03-23  
**Reviewer**: Phase 3 QA Agent  
**Verdict**: ✅ **PASS**

---

## Build Validation Status

> **Build validation skipped — not on NixOS.**  
> This review was performed on Windows. `nix flake check` and `nixos-rebuild dry-build` cannot be executed in this environment.  
> All validation below is static analysis only.

---

## Spec Compliance Checklist

All 15 spec requirements were verified against the implementation.

| # | Check | File | Result |
|---|-------|------|--------|
| 1 | `nix-cachyos-kernel` input: `url = "github:xddxdd/nix-cachyos-kernel/release"` with NO `inputs.nixpkgs.follows` | `flake.nix` | ✅ PASS |
| 2 | `outputs` signature destructures `nix-cachyos-kernel` | `flake.nix` | ✅ PASS |
| 3 | `cachyosOverlayModule` defined in `let` block as an attrset closure | `flake.nix` | ✅ PASS |
| 4 | `cachyosOverlayModule` included in `commonModules` | `flake.nix` | ✅ PASS |
| 5 | `nixosModules.base` has inline `nixpkgs.overlays = [ nix-cachyos-kernel.overlays.default ]` | `flake.nix` | ✅ PASS |
| 6 | `nixosModules.asus = ./modules/asus.nix` exported | `flake.nix` | ✅ PASS |
| 7 | `performance.nix` uses `pkgs.cachyosKernels.linuxPackages-cachyos-bore` | `modules/performance.nix` | ✅ PASS |
| 8 | 4 substituters present (cache.nixos.org, nix-gaming, attic.xuyh0120.win/lantian, cache.garnix.io) | `configuration.nix` | ✅ PASS |
| 9 | 4 trusted-public-keys present (all correct format) | `configuration.nix` | ✅ PASS |
| 10 | `modules/asus.nix` has `services.asusd.enable`, `enableUserService`, `services.supergfxd.enable`, `pkgs.asusctl` | `modules/asus.nix` | ✅ PASS |
| 11 | `hosts/amd.nix` imports `../modules/asus.nix` | `hosts/amd.nix` | ✅ PASS |
| 12 | `hosts/nvidia.nix` imports `../modules/asus.nix` | `hosts/nvidia.nix` | ✅ PASS |
| 13 | `hosts/vm.nix` does NOT import asus.nix | `hosts/vm.nix` | ✅ PASS |
| 14 | `modules/gpu/vm.nix` retains `lib.mkForce pkgs.linuxPackages` | `modules/gpu/vm.nix` | ✅ PASS |
| 15 | `system.stateVersion = "24.11"` unchanged | `configuration.nix` | ✅ PASS |

**Spec compliance: 15/15 (100%)**

---

## Static Analysis Findings

### flake.nix

**Nix Syntax — PASS**

```nix
inputs = {
  nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  nix-gaming = {
    url = "github:fufexan/nix-gaming";
    inputs.nixpkgs.follows = "nixpkgs";        # ✅ correct
  };
  home-manager = {
    url = "github:nix-community/home-manager/release-25.05";
    inputs.nixpkgs.follows = "nixpkgs";        # ✅ correct
  };
  nix-cachyos-kernel = {
    url = "github:xddxdd/nix-cachyos-kernel/release";
                                               # ✅ NO follows — intentional and correctly documented
  };
};
```

- `inputs` block: valid attribute set syntax ✅
- `nix-cachyos-kernel` has no `inputs.nixpkgs.follows` as required — correctly documented in an inline comment ✅
- `commonModules` is a Nix list `[ ... ]` with space-separated items, no commas ✅
- `cachyosOverlayModule` is a bare attrset (not a function), valid NixOS module form ✅
- `nixosModules.base` uses `{ ... }:` (ignores all args), returns attrset with `imports` and `nixpkgs.overlays` — correct NixOS module pattern ✅
- `nixosModules` attrset has valid attribute syntax with five keys: `base`, `gpuAmd`, `gpuNvidia`, `gpuVm`, `asus` — all valid ✅

**Overlay Architecture — PASS**

The overlay is applied via two distinct paths, one for each consumption model:

| Consumption model | Where overlay is applied | Reason |
|---|---|---|
| Direct `nixosConfigurations.*` | `cachyosOverlayModule` in `commonModules` | Shared across all three configs |
| Thin wrapper via `nixosModules.base` | Inline `nixpkgs.overlays` in `nixosModules.base` | External flake doesn't see `commonModules` |

No duplication: neither path overlaps with the other. ✅

**Module evaluation ordering — PASS**

`nixpkgs.overlays` is a NixOS module option that is resolved during `pkgs` construction, before any module option expressions access `pkgs`. Therefore `pkgs.cachyosKernels` will be present when `performance.nix` evaluates `boot.kernelPackages`. ✅

---

### modules/performance.nix

**Nix Syntax — PASS**

```nix
boot.kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-bore;
```

- Per the Nix language specification, identifiers are defined as `[a-zA-Z_][a-zA-Z0-9_'-]*`. The hyphen `-` is explicitly permitted in Nix identifiers. The lexer uses maximal munch, so `linuxPackages-cachyos-bore` is tokenized as a single `ID` token, not as subtraction. ✅
- Comment block is thorough, lists all alternatives, clearly documents the overlay dependency and vm.nix override relationship ✅
- All other performance tuning settings (ZRAM, sysctl, kernel params, Plymouth, governor) are unchanged and correct ✅

---

### configuration.nix

**Binary caches — PASS**

```nix
substituters = [
  "https://cache.nixos.org"
  "https://nix-gaming.cachix.org"
  "https://attic.xuyh0120.win/lantian"   # CachyOS primary (Hydra CI)
  "https://cache.garnix.io"              # CachyOS fallback (Garnix CI)
];
trusted-public-keys = [
  "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
  "nix-gaming.cachix.org-1:nbjlureqMbRAxR1gJ/f3hxemL9svXaZF/Ees8vCUUs4="
  "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc="
  "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
];
```

All four keys are in the correct Nix binary cache format (`name:base64_ed25519_pubkey`). Each base64 segment is 44 characters (32-byte ed25519 public key, base64-encoded with padding), which is correct.

| Key | Format | Length | Assessment |
|-----|--------|--------|------------|
| `cache.nixos.org-1:6NCHdD59...hjY=` | `name:base64` | 44 | ✅ |
| `nix-gaming.cachix.org-1:nbjl...s4=` | `name:base64` | 44 | ✅ |
| `lantian:EeAUQ+W+...vHc=` | `name:base64` | 44 | ✅ |
| `cache.garnix.io:CTFPy...r9g=` | `name:base64` | 44 | ✅ |

**`system.stateVersion` — PASS**

`system.stateVersion = "24.11";` — unchanged ✅

---

### modules/asus.nix

**Module header — PASS**

```nix
{ config, pkgs, lib, ... }:
```

Standard NixOS module signature. `lib` is present (required for any future `lib.mkIf` usage) ✅

**Service configuration — PASS**

```nix
services.asusd = {
  enable = true;
  enableUserService = true;   # asusd-user per-user LED control
};
services.supergfxd.enable = true;
```

- `services.asusd.enable = true` — enables the main daemon ✅
- `services.asusd.enableUserService = true` — enables `asusd-user` per-user Aura service ✅
- `services.supergfxd.enable = true` — explicit (overrides the `mkDefault true` set by asusd.nix at lower priority) ✅
- `environment.systemPackages = with pkgs; [ asusctl ]` — installs CLI + ROG Control Center GUI ✅
- `pkgs.supergfxctl` is installed automatically by the `supergfxd` NixOS module — not duplicated here ✅

**Safety note in header — PASS**

Header comment correctly documents that:
- asusd/supergfxd exit gracefully on non-ASUS hardware ✅
- No kernel module additions needed (auto-loaded via udev) ✅
- No extra groups needed (polkit/D-Bus + wheel) ✅
- Explicit warning: DO NOT import in hosts/vm.nix ✅

---

### hosts/amd.nix

```nix
imports = [
  ../configuration.nix
  ../modules/gpu/amd.nix
  ../modules/asus.nix      # ✅ correctly imported
];
```

---

### hosts/nvidia.nix

```nix
imports = [
  ../configuration.nix
  ../modules/gpu/nvidia.nix
  ../modules/asus.nix      # ✅ correctly imported
];
```

---

### hosts/vm.nix

```nix
imports = [
  ../configuration.nix
  ../modules/gpu/vm.nix    # ✅ asus.nix NOT present
];
networking.hostName = "vexos-vm";
```

asus.nix is absent. ✅

---

### modules/gpu/vm.nix

```nix
# zen kernel doesn't build VirtualBox GuestAdditions cleanly; use LTS instead.
# zen provides no benefit in a VM environment.
boot.kernelPackages = lib.mkForce pkgs.linuxPackages;
```

**LTS override preserved — PASS** ✅  
`lib.mkForce` (priority 1000) correctly overrides the default-priority (100) assignment of `pkgs.cachyosKernels.linuxPackages-cachyos-bore` in `performance.nix`. ✅

**MINOR ISSUE — Stale comment**: The comment still references "zen kernel" but the default kernel is now CachyOS BORE. The override logic and the functional behavior are completely correct; only the comment text is outdated. This does not affect operation.

---

## Architecture Consistency Review

### Overlay dual-path analysis

```
Direct nixosConfigurations.*:
  commonModules = [
    /etc/nixos/hardware-configuration.nix
    nix-gaming.nixosModules.pipewireLowLatency
    cachyosOverlayModule          ← overlay here
  ]
  Each host file appends → includes performance.nix (via configuration.nix)

Thin-wrapper nixosModules.base:
  nixosModules.base = { ... }: {
    imports = [
      nix-gaming.nixosModules.pipewireLowLatency
      ./configuration.nix         ← includes performance.nix
    ];
    nixpkgs.overlays = [ nix-cachyos-kernel.overlays.default ];  ← overlay here
  }
```

Both paths correctly ensure the overlay is applied before `pkgs.cachyosKernels` is accessed. ✅

### vm.nix kernel override analysis

```
performance.nix:
  boot.kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-bore;
  # Priority: 100 (default)

modules/gpu/vm.nix:
  boot.kernelPackages = lib.mkForce pkgs.linuxPackages;
  # Priority: 1000 (mkForce)
  # Result: LTS kernel wins in vexos-vm ✅
```

The overlay is applied in all three configurations (harmless in vm — the overlay just adds attributes to `pkgs`), but the `lib.mkForce` override ensures the VM uses `pkgs.linuxPackages` (LTS). ✅

### asus.nix isolation

| Build | asus.nix imported? | Expected |
|---|---|---|
| `vexos-amd` (hosts/amd.nix) | ✅ Yes | ✅ Correct |
| `vexos-nvidia` (hosts/nvidia.nix) | ✅ Yes | ✅ Correct |
| `vexos-vm` (hosts/vm.nix) | ❌ No | ✅ Correct |

---

## Security Review

### Binary cache trust model

All four caches and their associated public keys are from well-known, documented sources:

| Cache URL | Key name | Source |
|---|---|---|
| `https://cache.nixos.org` | `cache.nixos.org-1` | NixOS official cache — universally trusted |
| `https://nix-gaming.cachix.org` | `nix-gaming.cachix.org-1` | fufexan/nix-gaming official cache |
| `https://attic.xuyh0120.win/lantian` | `lantian` | xddxdd's personal Hydra CI (nix-cachyos-kernel primary) |
| `https://cache.garnix.io` | `cache.garnix.io` | Garnix public CI cache (nix-cachyos-kernel fallback) |

- No hardcoded secrets or credentials ✅
- No world-readable private keys ✅
- Binary cache trust is declarative (no `trusted-users` escalation needed) ✅
- Cache URLs use HTTPS ✅

### hardware-configuration.nix

Not present in the repository (tracked by git). The path `/etc/nixos/hardware-configuration.nix` is referenced in `commonModules` only as a host-side path reference. ✅

### No insecure configurations

- No `nix.settings.sandbox = false` ✅
- No `nix.settings.trusted-users = [ "..." ]` (only keys for binary caches) ✅
- No world-writable files configured ✅

---

## Issues Summary

| Severity | Location | Issue | Recommendation |
|----------|----------|-------|----------------|
| MINOR | `modules/gpu/vm.nix` | Comment says "zen kernel" but default kernel is now CachyOS BORE | Update comment: `# CachyOS kernel doesn't build VirtualBox GuestAdditions cleanly; use LTS instead.` |
| INFORMATIONAL | All files | Build validation skipped (Windows) | Run `nix flake check` and `nixos-rebuild dry-build` on NixOS host before pushing |

**No CRITICAL issues found.**  
**No NEEDS_REFINEMENT items.**

---

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A+ |
| Best Practices | 95% | A |
| Functionality | 100% | A+ |
| Code Quality | 95% | A |
| Security | 100% | A+ |
| Performance | 100% | A+ |
| Consistency | 95% | A |
| Build Success | N/A | — (static analysis only; skipped on Windows) |

**Overall Grade: A (98%)**

> Build Success is excluded from the grade calculation. If the build is confirmed to pass on NixOS, the overall grade is A+ (99%).

---

## Final Verdict

### ✅ PASS

All 15 specification compliance checks pass. No critical issues. No blocking syntax errors found via static analysis. Architecture is sound: the CachyOS overlay is correctly applied in both direct-build and thin-wrapper consumption paths; the VM LTS kernel override is preserved; ASUS module isolation is correct.

The single MINOR issue (stale comment in vm.nix) does not affect functionality and does not block this phase.

**Recommendation**: Proceed to Phase 6 Preflight Validation. Before executing the switch on the actual host, confirm `nix flake check` passes (verifies all three outputs evaluate cleanly) and run at least one `nixos-rebuild dry-build` to confirm no attribute resolution errors for `pkgs.cachyosKernels.linuxPackages-cachyos-bore`.
