# Specification: CachyOS Kernel + ASUS Hardware Support
**Feature**: `cachyos_asus`  
**Phase**: 1 — Research & Specification  
**Date**: 2026-03-23  
**Status**: READY FOR IMPLEMENTATION

---

## Table of Contents

1. [Current State Analysis](#current-state-analysis)
2. [Problem Definition / Motivation](#problem-definition--motivation)
3. [Research Summary & Sources](#research-summary--sources)
4. [Critical Finding: chaotic-nyx is DEAD — Use nix-cachyos-kernel](#critical-finding-chaotic-nyx-is-dead--use-nix-cachyos-kernel)
5. [Proposed Solution Architecture](#proposed-solution-architecture)
6. [Feature 1: CachyOS Kernel — Implementation Plan](#feature-1-cachyos-kernel--implementation-plan)
7. [Feature 2: ASUS Hardware Support — Implementation Plan](#feature-2-asus-hardware-support--implementation-plan)
8. [Exact File Changes](#exact-file-changes)
9. [Risks and Mitigations](#risks-and-mitigations)
10. [Decisions Made](#decisions-made)

---

## Current State Analysis

### Repository layout (flat module architecture)

```
flake.nix                   — Flake inputs, outputs, three nixosConfigurations
configuration.nix            — Shared base: imports all modules, users, nix settings
hosts/
  amd.nix                   — imports configuration.nix + modules/gpu/amd.nix
  nvidia.nix                — imports configuration.nix + modules/gpu/nvidia.nix
  vm.nix                    — imports configuration.nix + modules/gpu/vm.nix
modules/
  performance.nix            — *** Line 12: boot.kernelPackages = pkgs.linuxPackages_zen ***
  gpu/
    vm.nix                  — *** lib.mkForce pkgs.linuxPackages (LTS override — MUST stay) ***
    amd.nix, nvidia.nix     — GPU-specific config
  audio.nix, gaming.nix, desktop.nix, network.nix, controllers.nix, flatpak.nix
template/
  etc-nixos-flake.nix       — Thin wrapper for hosts: consumes nixosModules.base
scripts/
  preflight.sh              — CI validation script
```

### Current flake inputs

```nix
inputs = {
  nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  nix-gaming = {
    url = "github:fufexan/nix-gaming";
    inputs.nixpkgs.follows = "nixpkgs";
  };
  home-manager = {
    url = "github:nix-community/home-manager/release-25.05";
    inputs.nixpkgs.follows = "nixpkgs";
  };
};
```

### Current kernel setup

- **performance.nix line 12**: `boot.kernelPackages = pkgs.linuxPackages_zen;`
- **modules/gpu/vm.nix**: `boot.kernelPackages = lib.mkForce pkgs.linuxPackages;` — LTS for VM, must be preserved
- All three outputs share `commonModules` which includes `performance.nix` via `configuration.nix`

### Current nix binary caches (in configuration.nix)

```nix
substituters = [
  "https://cache.nixos.org"
  "https://nix-gaming.cachix.org"
];
trusted-public-keys = [
  "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
  "nix-gaming.cachix.org-1:nbjlureqMbRAxR1gJ/f3hxemL9svXaZF/Ees8vCUUs4="
];
```

### User: `nimda`

Current `extraGroups`: `[ "wheel" "networkmanager" "gamemode" "audio" "input" "plugdev" ]`

### specialArgs

All three `nixosSystem` calls have `specialArgs = { inherit inputs; }` — `inputs` is available in any module.

---

## Problem Definition / Motivation

### Feature 1: CachyOS Kernel

`linuxPackages_zen` (Zen kernel) provides good desktop/gaming latency but lacks:
- **BORE scheduler** (Burst-Oriented Response Enhancer) — designed specifically for interactive/gaming workloads; outperforms Zen's CFS for this use case
- **CachyOS-specific patches**: le9uo memory management patch, AMDGPU min_powercap override, AMD P-state enhancements, ASUS hardware compatibility patches, SCX sched-ext framework support
- **ROG hardware patches**: CachyOS kernel explicitly includes "Extended ASUS hardware compatibility patches" (source: linux-cachyos README)
- **500 MHz → 1000 Hz timer frequency**: CachyOS defaults to 1000 Hz vs Zen's 300 Hz, further reducing input latency
- **Thin LTO & AutoFDO**: Better code-gen via profile-guided optimization in `linux-cachyos-bore`

### Feature 2: ASUS Hardware Support

ASUS ROG/TUF laptops have hardware features inaccessible without `asusd` + `supergfxd`:
- Fan curve control (per-profile CPU/GPU fan curves)
- Battery charge limit (e.g. 80% for longevity)
- Power/thermal profiles (Silent / Balanced / Performance / Turbo)
- Keyboard backlight (Aura RGB) control
- GPU MUX switch management (integrated/hybrid/dedicated mode)
- Anime Matrix LED (ROG-specific display on lid)

Bazzite includes all of these via `asusctl`. This feature brings vexos-nix to parity.

---

## Research Summary & Sources

| # | Source | Finding |
|---|--------|---------|
| 1 | [github.com/chaotic-cx/nyx](https://github.com/chaotic-cx/nyx) | **ARCHIVED December 8, 2025** — do NOT use |
| 2 | [github.com/CachyOS/linux-cachyos](https://github.com/CachyOS/linux-cachyos) README | Officially recommends `xddxdd/nix-cachyos-kernel` for NixOS |
| 3 | [github.com/xddxdd/nix-cachyos-kernel](https://github.com/xddxdd/nix-cachyos-kernel) | Active (commit 14 min before research); full integration docs; `release` branch has CI-verified builds |
| 4 | [nixpkgs/nixos-25.05/modules/services/hardware/asusd.nix](https://github.com/NixOS/nixpkgs/blob/nixos-25.05/nixos/modules/services/hardware/asusd.nix) | `services.asusd.enable` fully supported; auto-enables supergfxd; version 6.1.12 |
| 5 | [nixpkgs/nixos-25.05/modules/services/hardware/supergfxd.nix](https://github.com/NixOS/nixpkgs/blob/nixos-25.05/nixos/modules/services/hardware/supergfxd.nix) | `services.supergfxd.enable`; installs `pkgs.supergfxctl`; no hardware guard |
| 6 | [nixpkgs/nixos-25.05/pkgs/by-name/as/asusctl/package.nix](https://github.com/NixOS/nixpkgs/blob/nixos-25.05/pkgs/by-name/as/asusctl/package.nix) | `asusctl` v6.1.12 in nixos-25.05; builds `rog-control-center` binary bundled |
| 7 | Context7 `gitlab_asus-linux/asusctl` | Service name is `asusd`; user service is `asusd-user`; permissions via polkit/D-Bus |
| 8 | [search.nixos.org options: asusd](https://search.nixos.org/options?query=asusd) | Full option list: `services.asusd.enable`, `.enableUserService`, `.package`, `.asusdConfig`, etc. |
| 9 | [search.nixos.org packages: supergfxctl](https://search.nixos.org/packages?query=supergfxctl) | `supergfxctl` v5.2.7 + `supergfxctl-plasmoid` v2.1.1 available in nixpkgs |

---

## Critical Finding: chaotic-nyx is DEAD — Use nix-cachyos-kernel

> **chaotic-cx/nyx was archived on December 8, 2025.** The repository's own README states:
> *"Originally launched at 2023-03-28 and killed at 2025-12-08"*

The original request mentioned `chaotic-nyx` as the source for CachyOS kernels. This is **no longer viable**.

**Official replacement endorsed by CachyOS themselves** (from their own `linux-cachyos` README, NixOS section):

> *"Precompiled kernels available through the xddxdd/nix-cachyos-kernel repository"*

`xddxdd/nix-cachyos-kernel` is:
- Actively maintained (commits verified as of research date)
- The official CachyOS-recommended NixOS integration
- Backed by Hydra CI at `hydra.lantian.pub` for binary cache
- Uses the `release` branch for CI-verified, cache-available builds

---

## Proposed Solution Architecture

### Feature 1: CachyOS Kernel

**Integration approach**: Overlay-based via `nix-cachyos-kernel.overlays.default`

The overlay adds `pkgs.cachyosKernels.*` to the nixpkgs attribute set. It is applied via a `nixpkgs.overlays` module option, which works correctly in both:
- Direct `nixosConfigurations.*` usage (this repo's three outputs)
- Consumed `nixosModules.base` output (used by `/etc/nixos/flake.nix` thin wrapper)

The overlay is defined as a **closure module** directly in `flake.nix` (capturing `nix-cachyos-kernel` from the outputs function scope). This avoids requiring `inputs` in individual modules.

**Kernel variant chosen**: `linuxPackages-cachyos-bore`
- BORE scheduler: best available scheduler for gaming/interactive workloads
- Default 1000 Hz timer, full preemption, CachyOS patches, ASUS hardware patches
- Not LTO (stable, compatible with out-of-tree modules like NVIDIA and VirtualBox Guest Additions)

**vm.nix safety**: `modules/gpu/vm.nix` uses `lib.mkForce pkgs.linuxPackages`. The `mkForce` priority (1000) overrides the default assignment priority (100) in `performance.nix`. The overlay is applied in all configurations (harmless), but the actual kernel selection in vm remains LTS. ✓

**Binary caches**:
- Primary: `https://attic.xuyh0120.win/lantian` (Hydra CI-backed, xddxdd's personal Attic instance)
- Fallback: `https://cache.garnix.io` (Garnix CI)
- Both are required; Garnix occasionally runs out of free plan build time

### Feature 2: ASUS Hardware Support

**New file**: `modules/asus.nix` — ASUS-specific hardware module following existing module patterns

**Import**: Only in `hosts/amd.nix` and `hosts/nvidia.nix` (physical machine configs); NOT in `hosts/vm.nix`

**NixOS module options used** (all confirmed in nixpkgs 25.05):
- `services.asusd.enable = true` — main daemon (fan, LED, power profiles, battery limit, GPU MUX)
- `services.asusd.enableUserService = true` — per-user Aura LED control via `asusd-user` service
- `services.supergfxd.enable = true` — GPU switching daemon (auto-enabled by asusd via `mkDefault`, but explicit is clearer)

**Critical insight from asusd.nix source**:
```nix
services.supergfxd.enable = lib.mkDefault true;  # auto-enabled by asusd!
```
Enabling `services.asusd` automatically enables `services.supergfxd` at `mkDefault` priority. Declaring `services.supergfxd.enable = true` explicitly overrides the default to ensure it is always on.

**Packages**: `pkgs.asusctl` (v6.1.12 in nixos-25.05) bundles both the CLI (`asusctl`) and the GUI (`rog-control-center`). `supergfxd.nix` module installs `pkgs.supergfxctl` automatically via `environment.systemPackages`. No separate GUI package needed.

**Non-ASUS hardware safety**: Neither `asusd.nix` nor `supergfxd.nix` have DMI/hardware guards. On non-ASUS hardware:
- `asusd` fails to start (can't find ASUS platform device) — systemd reports the unit as failed, then stops. Harmless.
- `supergfxd` exits gracefully if no switchable GPU is found. Harmless.
Both modules are safe to include universally in physical machine configs.

**User groups**: No new groups required. `asusd` uses polkit + D-Bus for authorization. The `nimda` user's existing `wheel` membership provides full polkit admin access.

**Kernel modules**: ASUS hardware kernel modules (`asus-nb-wmi`, `asus-wmi`, `platform_profile`) are loaded automatically by udev via the kernel's built-in hardware detection. No explicit `boot.kernelModules` additions are needed.

---

## Feature 1: CachyOS Kernel — Implementation Plan

### Step 1: Add `nix-cachyos-kernel` input to `flake.nix`

In the `inputs` block, add:

```nix
# CachyOS kernel — official NixOS packaging.
# `release` branch: CI-verified builds present in binary cache.
# CRITICAL: Do NOT add inputs.nixpkgs.follows here.
# The version pinning between CachyOS patches and kernel source is managed
# internally by the release branch CI. Adding nixpkgs.follows breaks this.
nix-cachyos-kernel = {
  url = "github:xddxdd/nix-cachyos-kernel/release";
};
```

### Step 2: Update outputs function signature in `flake.nix`

Change:
```nix
outputs = { self, nixpkgs, nix-gaming, ... }@inputs:
```
To:
```nix
outputs = { self, nixpkgs, nix-gaming, nix-cachyos-kernel, ... }@inputs:
```

### Step 3: Add closure overlay module to `let` block in `flake.nix`

In the `let ... in` block, add:

```nix
# Inline NixOS module that applies the CachyOS kernel overlay.
# Using a closure here (capturing nix-cachyos-kernel from the outputs scope)
# so the overlay works when nixosModules.base is consumed by external flakes
# (template/etc-nixos-flake.nix) without needing specialArgs.
cachyosOverlayModule = {
  nixpkgs.overlays = [ nix-cachyos-kernel.overlays.default ];
};
```

### Step 4: Add `cachyosOverlayModule` to `commonModules` in `flake.nix`

```nix
commonModules = [
  /etc/nixos/hardware-configuration.nix
  nix-gaming.nixosModules.pipewireLowLatency
  cachyosOverlayModule   # ← ADD
];
```

### Step 5: Add `cachyosOverlayModule` to `nixosModules.base` in `flake.nix`

```nix
nixosModules = {
  base = { ... }: {
    imports = [
      nix-gaming.nixosModules.pipewireLowLatency
      ./configuration.nix
    ];
    nixpkgs.overlays = [ nix-cachyos-kernel.overlays.default ];  # ← ADD (closed over)
  };
  gpuAmd    = ./modules/gpu/amd.nix;
  gpuNvidia = ./modules/gpu/nvidia.nix;
  gpuVm     = ./modules/gpu/vm.nix;
  asus      = ./modules/asus.nix;  # ← ADD (see Feature 2)
};
```

### Step 6: Update `modules/performance.nix` — replace kernel

Change **only line 12**:

```nix
# Old:
boot.kernelPackages = pkgs.linuxPackages_zen;

# New:
# CachyOS BORE: Burst-Oriented Response Enhancer scheduler for gaming.
# Overlay applied in flake.nix (cachyosOverlayModule) makes pkgs.cachyosKernels available.
# vm.nix overrides this with lib.mkForce pkgs.linuxPackages (LTS) — VM is unaffected.
boot.kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-bore;
```

Also update the comment block above the line:

```nix
# ── Kernel selection ──────────────────────────────────────────────────────
# CachyOS BORE: Burst-Oriented Response Enhancer scheduler — best for gaming/interactive.
# Patches: ASUS hardware, AMD P-state, le9uo memory management, HDR, ACS override.
# Timer: 1000 Hz, full preemption. Thin LTO not used (avoids out-of-tree module issues).
# Source: github:xddxdd/nix-cachyos-kernel/release (official CachyOS NixOS packaging).
# Alternatives in pkgs.cachyosKernels.*:
#   linuxPackages-cachyos-latest  — EEVDF scheduler (general-purpose)
#   linuxPackages-cachyos-eevdf   — Pure EEVDF
#   linuxPackages-cachyos-deckify — Steam Deck optimized
#   linuxPackages-cachyos-lts     — CachyOS LTS (for stability)
```

### Step 7: Add CachyOS binary caches to `configuration.nix`

In `nix.settings`, extend the existing `substituters` and `trusted-public-keys` lists:

```nix
substituters = [
  "https://cache.nixos.org"
  "https://nix-gaming.cachix.org"
  # CachyOS kernel binary caches (xddxdd/nix-cachyos-kernel)
  "https://attic.xuyh0120.win/lantian"  # Primary: Hydra CI-backed
  "https://cache.garnix.io"             # Fallback: Garnix CI
];
trusted-public-keys = [
  "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
  "nix-gaming.cachix.org-1:nbjlureqMbRAxR1gJ/f3hxemL9svXaZF/Ees8vCUUs4="
  # CachyOS kernel binary caches
  "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc="
  "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
];
```

---

## Feature 2: ASUS Hardware Support — Implementation Plan

### Step 8: Create `modules/asus.nix`

Full file content:

```nix
# modules/asus.nix
# ASUS ROG/TUF laptop hardware support: asusd daemon, ROG Control Center GUI,
# supergfxctl GPU switching. Mirrors Bazzite's ASUS feature set.
#
# Safe on non-ASUS hardware: asusd and supergfxd exit gracefully when ASUS
# platform drivers are absent. No kernel module additions required — ASUS
# drivers (asus-nb-wmi, asus-wmi, platform_profile) are auto-loaded by udev.
#
# User permissions: managed via polkit + D-Bus. No extra groups required;
# the nimda user's existing 'wheel' membership grants full polkit admin access.
#
# DO NOT import in hosts/vm.nix — not applicable in VM guests.
{ config, pkgs, lib, ... }:
{
  # asusd: ASUS ROG daemon — fan curves, battery charge limit, power/thermal profiles,
  # keyboard backlight (Aura), GPU MUX switching, Anime Matrix LED.
  # Enabling this also enables services.supergfxd via lib.mkDefault (see nixpkgs source).
  services.asusd = {
    enable = true;
    enableUserService = true;  # asusd-user: per-user Aura LED profile control
  };

  # supergfxd: GPU switching daemon (integrated / hybrid / VFIO / dedicated modes).
  # Explicitly set to ensure it's always enabled regardless of asusd's mkDefault.
  # The supergfxd module auto-installs pkgs.supergfxctl into environment.systemPackages.
  services.supergfxd.enable = true;

  # asusctl CLI tool + rog-control-center GUI (bundled in the same package, v6.1.12).
  # supergfxctl is already added to systemPackages by the supergfxd NixOS module.
  environment.systemPackages = with pkgs; [
    asusctl  # CLI: asusctl; GUI: rog-control-center (both included in this package)
  ];
}
```

### Step 9: Add ASUS module import to `hosts/amd.nix`

```nix
# hosts/amd.nix
{ ... }:
{
  imports = [
    ../configuration.nix
    ../modules/gpu/amd.nix
    ../modules/asus.nix   # ← ADD: ASUS ROG/TUF hardware daemon + ROG Control Center
  ];
}
```

### Step 10: Add ASUS module import to `hosts/nvidia.nix`

```nix
# hosts/nvidia.nix
{ ... }:
{
  imports = [
    ../configuration.nix
    ../modules/gpu/nvidia.nix
    ../modules/asus.nix   # ← ADD: ASUS ROG/TUF hardware daemon + ROG Control Center
  ];
}
```

---

## Exact File Changes

### Summary table

| File | Action | Change |
|------|--------|--------|
| `flake.nix` | Modify | Add `nix-cachyos-kernel` input; update outputs args; add `cachyosOverlayModule`; add to `commonModules`; add to `nixosModules.base`; add `nixosModules.asus` |
| `modules/performance.nix` | Modify | Replace `pkgs.linuxPackages_zen` with `pkgs.cachyosKernels.linuxPackages-cachyos-bore`; update comment |
| `configuration.nix` | Modify | Add 2 substituters and 2 trusted-public-keys for CachyOS binary caches |
| `modules/asus.nix` | Create | New ASUS hardware module |
| `hosts/amd.nix` | Modify | Add `../modules/asus.nix` to imports |
| `hosts/nvidia.nix` | Modify | Add `../modules/asus.nix` to imports |
| `modules/gpu/vm.nix` | No change | `lib.mkForce pkgs.linuxPackages` preserved |
| `hosts/vm.nix` | No change | No ASUS module — VMs don't have ASUS hardware |
| `configuration.nix` — `system.stateVersion` | No change | MUST NOT be altered |

### Complete `flake.nix` after changes

```nix
{
  description = "vexos-nix — Personal NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

    # nix-gaming: low-latency PipeWire module, SteamOS platform optimisations, Wine-GE packages
    nix-gaming = {
      url = "github:fufexan/nix-gaming";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # home-manager: optional, for user-level dotfiles (future use)
    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # CachyOS kernel — official NixOS packaging by xddxdd.
    # `release` branch: CI-verified, binary cache guaranteed.
    # CRITICAL: Do NOT add inputs.nixpkgs.follows — breaks kernel/patch version sync.
    nix-cachyos-kernel = {
      url = "github:xddxdd/nix-cachyos-kernel/release";
    };
  };

  outputs = { self, nixpkgs, nix-gaming, nix-cachyos-kernel, ... }@inputs:
  let
    system = "x86_64-linux";

    # Inline NixOS module applying the CachyOS kernel overlay.
    # Closed over nix-cachyos-kernel so it works in nixosModules.base without specialArgs.
    cachyosOverlayModule = {
      nixpkgs.overlays = [ nix-cachyos-kernel.overlays.default ];
    };

    # Modules shared across all three configurations
    commonModules = [
      # Hardware config generated by nixos-generate-config (lives on the host, NOT in this repo)
      /etc/nixos/hardware-configuration.nix

      # nix-gaming: declarative low-latency PipeWire tuning
      nix-gaming.nixosModules.pipewireLowLatency

      # CachyOS kernel overlay: makes pkgs.cachyosKernels.* available
      cachyosOverlayModule
    ];
  in
  {
    # ── AMD GPU build ────────────────────────────────────────────────────────
    nixosConfigurations.vexos-amd = nixpkgs.lib.nixosSystem {
      inherit system;
      modules = commonModules ++ [ ./hosts/amd.nix ];
      specialArgs = { inherit inputs; };
    };

    # ── NVIDIA GPU build ─────────────────────────────────────────────────────
    nixosConfigurations.vexos-nvidia = nixpkgs.lib.nixosSystem {
      inherit system;
      modules = commonModules ++ [ ./hosts/nvidia.nix ];
      specialArgs = { inherit inputs; };
    };

    # ── VM guest build (QEMU/KVM + VirtualBox) ───────────────────────────────
    nixosConfigurations.vexos-vm = nixpkgs.lib.nixosSystem {
      inherit system;
      modules = commonModules ++ [ ./hosts/vm.nix ];
      specialArgs = { inherit inputs; };
    };

    # ── NixOS modules (consumed by /etc/nixos/flake.nix on the host) ─────────
    nixosModules = {
      base = { ... }: {
        imports = [
          nix-gaming.nixosModules.pipewireLowLatency
          ./configuration.nix
        ];
        # CachyOS kernel overlay: closed over nix-cachyos-kernel from outputs scope
        nixpkgs.overlays = [ nix-cachyos-kernel.overlays.default ];
      };

      gpuAmd    = ./modules/gpu/amd.nix;
      gpuNvidia = ./modules/gpu/nvidia.nix;
      gpuVm     = ./modules/gpu/vm.nix;
      asus      = ./modules/asus.nix;  # ASUS ROG/TUF hardware support
    };
  };
}
```

---

## Risks and Mitigations

| Risk | Severity | Mitigation |
|------|----------|-----------|
| CachyOS kernel build failure (patch/version mismatch) | Medium | Use `release` branch (CI-verified). If build fails, fallback: replace `linuxPackages-cachyos-bore` with `linuxPackages-cachyos-lts` in performance.nix |
| NVIDIA out-of-tree module incompatibility with CachyOS BORE | Medium | BORE (non-LTO) variant maintains compatibility with nixpkgs NVIDIA modules. If issues arise, switch to `linuxPackages-cachyos-latest`. Do NOT use LTO variants with NVIDIA. |
| attic.xuyh0120.win binary cache downtime | Low | Garnix fallback is defined. Worst case: kernel compiles locally (~30-60 min). No service impact. |
| `asusd` service fails on non-ASUS hardware | Known/Safe | Confirmed harmless — systemd marks unit as failed, no crash or data loss. Both asusd and supergfxd handle missing hardware gracefully. |
| `services.asusd.enable` conflict with `services.supergfxd.enable` | None | asusd sets supergfxd via `lib.mkDefault`; explicit `enable = true` in asus.nix overrides at default priority. No conflict. |
| `nixpkgs.overlays` applied in VM (unnecessary but harmless) | Negligible | The overlay adds `pkgs.cachyosKernels.*` to the VM's pkgs, but vm.nix uses `lib.mkForce pkgs.linuxPackages` so the CachyOS kernel is never selected. Overlay itself has zero runtime cost. |
| `nix flake lock` adds nix-cachyos-kernel without `nixpkgs.follows` | By design | This is explicitly required per the nix-cachyos-kernel README: "Do not override its nixpkgs input, otherwise there can be mismatch between patches and kernel version." |

---

## Decisions Made

### Decision 1: `xddxdd/nix-cachyos-kernel` over `chaotic-nyx`

**Reason**: `chaotic-nyx` was archived and discontinued December 8, 2025. It is no longer maintained and must not be used. `xddxdd/nix-cachyos-kernel` is officially recommended by CachyOS themselves in their kernel repository README.

### Decision 2: `nix-cachyos-kernel/release` branch (not `master`)

**Reason**: The `release` branch tracks the latest CI-verified build that is guaranteed to be present in the binary cache. The `master` branch is bleeding-edge and may not have cached builds, requiring local compilation.

### Decision 3: `linuxPackages-cachyos-bore` as the gaming kernel variant

**Reason**: BORE (Burst-Oriented Response Enhancer) scheduler is specifically designed for interactive/gaming workloads. It is the most widely used CachyOS variant in gaming contexts. The non-LTO build is chosen over `linuxPackages-cachyos-bore-lto` for out-of-tree module compatibility (NVIDIA drivers, VirtualBox Guest Additions).

### Decision 4: Overlay approach via closure module (not `_module.args` or `specialArgs`)

**Reason**: A closure module in flake.nix captures `nix-cachyos-kernel.overlays.default` at outputs evaluation time. This approach works:
- For direct `nixosConfigurations.*` usage (in this repo)
- For `nixosModules.base` consumed by `/etc/nixos/flake.nix` (thin wrapper hosts)
Without a closure, modules consuming `nixosModules.base` would need to also have access to `inputs.nix-cachyos-kernel`, creating an external dependency.

### Decision 5: `overlays.default` over `overlays.pinned`

**Reason**: As of 2026-03-01, `nix-cachyos-kernel` switched to pre-patched kernel sources released by CachyOS directly (no longer patching nixpkgs kernels). Therefore, both `default` and `pinned` overlays are safe. `default` is preferred as it avoids initializing a second nixpkgs instance and respects `nixpkgs.config`.

### Decision 6: ASUS module imported in `hosts/amd.nix` and `hosts/nvidia.nix` only

**Reason**: VMs do not have ASUS hardware. The module pattern follows the existing GPU module pattern (per-host selective imports). A future `hosts/asus.nix` specialization is not needed — the existing amd/nvidia hosts are sufficient.

### Decision 7: No new user groups for `nimda`

**Reason**: `asusd` uses polkit + D-Bus authorization. The `nimda` user's existing `wheel` group membership gives full polkit admin access. `supergfxd` similarly uses polkit. No additional groups required.

### Decision 8: `enableUserService = true` for `services.asusd`

**Reason**: The `asusd-user` service enables per-user Aura LED profile control without requiring root. This matches Bazzite behavior and is useful on ASUS ROG hardware with RGB keyboards.

---

## Package Versions (Confirmed in nixpkgs 25.05)

| Package | NixOS Option / Attr | Version | Source |
|---------|---------------------|---------|--------|
| `asusctl` | `pkgs.asusctl` | 6.1.12 | [nixpkgs nixos-25.05](https://github.com/NixOS/nixpkgs/blob/nixos-25.05/pkgs/by-name/as/asusctl/package.nix) |
| `supergfxctl` | `pkgs.supergfxctl` | 5.2.7 | search.nixos.org (25.11, confirmed available) |
| `nix-cachyos-kernel` | `pkgs.cachyosKernels.*` | auto-synced with nixpkgs kernel | [release branch CI](https://hydra.lantian.pub/jobset/lantian/nix-cachyos-kernel) |

---

*Spec file path*: `c:\Projects\vexos-nix\.github\docs\subagent_docs\cachyos_asus_spec.md`
