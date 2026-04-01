# Bazzite Kernel Fix — Specification

**Feature Name:** `bazzite_kernel_fix`  
**Date:** 2026-04-01  
**Status:** Draft

---

## 1. Current State Analysis

### Affected Files
- `hosts/vm.nix` — defines `boot.kernelPackages` for the VM variant using a complex `lib.makeOverridable` wrapper
- `flake.nix` — exposes `packages.x86_64-linux.linux-bazzite` and `nixosModules.kernelBazzite`, both using `overrideAttrs` workarounds
- `flake.lock` — locks `kernel-bazzite` input at rev `d612bf2871f1b7e21a6acf13a8a359e655edefec`

### Current Kernel Priority Chain
| Source | Option | Priority |
|---|---|---|
| `modules/performance.nix` | `boot.kernelPackages = pkgs.linuxPackages_latest` | 100 (default) |
| `modules/gpu/vm.nix` | `boot.kernelPackages = lib.mkForce pkgs.linuxPackages` | 50 (`mkForce`) |
| `hosts/vm.nix` | `boot.kernelPackages = lib.mkOverride 49 (…bazziteKernel…)` | 49 |

`lib.mkOverride 49` has priority 49, which is numerically lower than 50, so it is **supposed to win** over `lib.mkForce` (priority 50). However, the current workaround implementation is failing in practice.

### Current Code in `hosts/vm.nix`

```nix
boot.kernelPackages = lib.mkOverride 49 (
  let
    rawKernel = inputs.kernel-bazzite.packages.x86_64-linux.linux-bazzite;
    kernelWithFeatures = rawKernel.overrideAttrs (old: {
      passthru = (old.passthru or {}) // {
        features = { ia32Emulation = true; efiBootStub = true; };
      };
    });
    bazziteKernel = lib.makeOverridable
      ({ features ? {}, randstructSeed ? "", kernelPatches ? [], ... }:
        kernelWithFeatures)
      {};
  in
  pkgs.linuxPackagesFor bazziteKernel
);
```

### Current Code in `flake.nix` — packages output

```nix
packages.x86_64-linux.linux-bazzite =
  kernel-bazzite.packages.x86_64-linux.linux-bazzite
  .overrideAttrs (old: {
    passthru = (old.passthru or {}) // {
      features = { ia32Emulation = true; efiBootStub = true; };
    };
  });
```

### Current Code in `flake.nix` — nixosModules.kernelBazzite

```nix
kernelBazzite = { pkgs, lib, ... }: {
  boot.kernelPackages = lib.mkOverride 49 (
    let
      rawKernel = kernel-bazzite.packages.x86_64-linux.linux-bazzite;
      kernelWithFeatures = rawKernel.overrideAttrs (old: {
        passthru = (old.passthru or {}) // {
          features = { ia32Emulation = true; efiBootStub = true; };
        };
      });
      bazziteKernel = lib.makeOverridable
        ({ features ? {}, randstructSeed ? "", kernelPatches ? [], ... }:
          kernelWithFeatures)
        {};
    in
    pkgs.linuxPackagesFor bazziteKernel
  );
};
```

---

## 2. Problem Definition

After `sudo nixos-rebuild switch --flake .#vexos-vm`, the running kernel is **Linux 6.12.77** (`pkgs.linuxPackages`, the LTS kernel from `modules/gpu/vm.nix`), NOT the Bazzite gaming kernel (`6.17.7-ba28` or newer). The Bazzite kernel should win at priority 49, but the rebuild either fails silently or produces the wrong result, leaving the system on its previous generation or forcing a fallback to 6.12.77.

---

## 3. Root Cause

The `kernel-bazzite` flake input is locked at rev `d612bf2871f1b7e21a6acf13a8a359e655edefec` ("update: build instructions", March 28, 2026). At that revision, `pkgs/linux-bazzite.nix` in the `vex-kernels` repository had a **strict 5-argument function signature**:

```nix
{ lib, fetchFromGitHub, fetchurl, linuxManualConfig, runCommand }:
```

It did **not** accept `features`, `randstructSeed`, or `kernelPatches`. When NixOS's `kernel.nix` module calls `kernel.override { features; randstructSeed; kernelPatches; }` during system closure evaluation, this strict signature causes an evaluation error or unexpected behavior.

The `lib.makeOverridable` wrapper in `hosts/vm.nix` and `nixosModules.kernelBazzite` was designed to intercept this call by wrapping the kernel derivation in a function that accepts and ignores those parameters. However, this workaround introduces indirection that can cause `pkgs.linuxPackagesFor` to produce an incorrect package set or for NixOS module assertions (e.g., `hardware.graphics.enable32Bit`, systemd-boot's `efiBootStub` assertion) to fail because `passthru.features` is not visible in the right place.

The combination of these issues means the build either fails (leaving the running system unchanged at 6.12.77 from a previous build) or the Bazzite kernel package set is not selected.

---

## 4. Proposed Solution Architecture

### Upstream Fix
The `vex-kernels` repository has already published a fix on `main`:

- **Commit `3b4182862015d45065f96ebc7b79d05cc2217784`** ("fix: kernel", March 28, 2026):
  - Updated `pkgs/linux-bazzite.nix` to accept `features ? {}` and `...` in its function signature, natively supporting NixOS's `kernel.override` call pattern
  - Appended `// { features = { ia32Emulation = true; efiBootStub = true; }; }` at the top level of the derivation, satisfying NixOS assertions

- **Commit `ce01769ecf6bc51b80b8cc5ad1f51e6c394a3283`** ("fix: verify success", March 29, 2026): Latest head of `main`; confirms fix is verified working

### Solution
1. **Update the `kernel-bazzite` flake input** to head of main (`ce01769ecf…`) via `nix flake update kernel-bazzite`
2. **Remove all workaround code** — `overrideAttrs`, `lib.makeOverridable`, `passthru.features` injection, and the intermediate `let` bindings — since the upstream derivation now handles these natively
3. **Simplify all three call sites** to direct `pkgs.linuxPackagesFor` calls on the upstream derivation reference

This eliminates the source of the breakage without any runtime behavior change for a correctly-built system.

---

## 5. Implementation Steps

1. **Update the flake input**
   ```bash
   cd /home/nimda/Projects/vexos-nix
   nix flake update kernel-bazzite
   ```
   This rewrites `flake.lock` to point `kernel-bazzite` at the latest `main` commit (`ce01769ecf6bc51b80b8cc5ad1f51e6c394a3283` or newer if main has advanced).

2. **Simplify `hosts/vm.nix`**
   Replace the entire `lib.mkOverride 49 ( let … in pkgs.linuxPackagesFor bazziteKernel )` block with the direct form:
   ```nix
   boot.kernelPackages = lib.mkOverride 49 (
     pkgs.linuxPackagesFor inputs.kernel-bazzite.packages.x86_64-linux.linux-bazzite
   );
   ```
   Remove all associated `let` bindings (`rawKernel`, `kernelWithFeatures`, `bazziteKernel`).

3. **Simplify `flake.nix` — `packages.x86_64-linux.linux-bazzite`**
   Replace the `.overrideAttrs` call with a direct pass-through:
   ```nix
   packages.x86_64-linux.linux-bazzite =
     kernel-bazzite.packages.x86_64-linux.linux-bazzite;
   ```

4. **Simplify `flake.nix` — `nixosModules.kernelBazzite`**
   Replace the entire `let … in pkgs.linuxPackagesFor bazziteKernel` block inside the module:
   ```nix
   kernelBazzite = { pkgs, lib, ... }: {
     boot.kernelPackages = lib.mkOverride 49 (
       pkgs.linuxPackagesFor kernel-bazzite.packages.x86_64-linux.linux-bazzite
     );
   };
   ```

5. **Update all inline comments** referencing the old workaround (see Section 7 below).

---

## 6. Code Changes

### 6.1 `hosts/vm.nix` — `boot.kernelPackages`

**Before:**
```nix
# Workaround: linux-bazzite at d612bf28 has a strict 5-arg signature.
# lib.makeOverridable intercepts kernel.override { features; randstructSeed; kernelPatches }
# and injects passthru.features so NixOS assertions don't fail.
boot.kernelPackages = lib.mkOverride 49 (
  let
    rawKernel = inputs.kernel-bazzite.packages.x86_64-linux.linux-bazzite;
    kernelWithFeatures = rawKernel.overrideAttrs (old: {
      passthru = (old.passthru or {}) // {
        features = { ia32Emulation = true; efiBootStub = true; };
      };
    });
    bazziteKernel = lib.makeOverridable
      ({ features ? {}, randstructSeed ? "", kernelPatches ? [], ... }:
        kernelWithFeatures)
      {};
  in
  pkgs.linuxPackagesFor bazziteKernel
);
```

**After:**
```nix
# Use mkOverride 49 to win over modules/gpu/vm.nix (mkForce = priority 50).
boot.kernelPackages = lib.mkOverride 49 (
  pkgs.linuxPackagesFor inputs.kernel-bazzite.packages.x86_64-linux.linux-bazzite
);
```

---

### 6.2 `flake.nix` — `packages.x86_64-linux.linux-bazzite`

**Before:**
```nix
# Inject passthru.features because linux-bazzite at d612bf28 lacks it.
packages.x86_64-linux.linux-bazzite =
  kernel-bazzite.packages.x86_64-linux.linux-bazzite
  .overrideAttrs (old: {
    passthru = (old.passthru or {}) // {
      features = { ia32Emulation = true; efiBootStub = true; };
    };
  });
```

**After:**
```nix
packages.x86_64-linux.linux-bazzite =
  kernel-bazzite.packages.x86_64-linux.linux-bazzite;
```

---

### 6.3 `flake.nix` — `nixosModules.kernelBazzite`

**Before:**
```nix
# Workaround: wrap with lib.makeOverridable to handle kernel.override call signature.
kernelBazzite = { pkgs, lib, ... }: {
  boot.kernelPackages = lib.mkOverride 49 (
    let
      rawKernel = kernel-bazzite.packages.x86_64-linux.linux-bazzite;
      kernelWithFeatures = rawKernel.overrideAttrs (old: {
        passthru = (old.passthru or {}) // {
          features = { ia32Emulation = true; efiBootStub = true; };
        };
      });
      bazziteKernel = lib.makeOverridable
        ({ features ? {}, randstructSeed ? "", kernelPatches ? [], ... }:
          kernelWithFeatures)
        {};
    in
    pkgs.linuxPackagesFor bazziteKernel
  );
};
```

**After:**
```nix
kernelBazzite = { pkgs, lib, ... }: {
  # Use mkOverride 49 to win over modules/gpu/vm.nix (mkForce = priority 50).
  boot.kernelPackages = lib.mkOverride 49 (
    pkgs.linuxPackagesFor kernel-bazzite.packages.x86_64-linux.linux-bazzite
  );
};
```

---

## 7. Comments to Delete or Update

The following comment blocks must be **removed or replaced** with brief single-line comments. They exist solely to explain the workaround that will be deleted:

### `hosts/vm.nix`
- Any comment referencing `d612bf28`, `d612bf2871f1b7e21a6acf13a8a359e655edefec`
- Any comment referencing `passthru.features`, `overrideAttrs`, `makeOverridable`
- Any comment explaining why `features`, `randstructSeed`, or `kernelPatches` are intercepted
- Any comment explaining the strict 5-argument signature workaround

**Replacement:** A single comment explaining why `lib.mkOverride 49` is needed:
```nix
# mkOverride 49 wins over modules/gpu/vm.nix which uses mkForce (priority 50).
```

### `flake.nix`
- Any comment referencing `d612bf28`, `d612bf2871f1b7e21a6acf13a8a359e655edefec`
- Any comment referencing `passthru.features` injection for the `packages.x86_64-linux.linux-bazzite` output
- Any comment explaining `.overrideAttrs` usage for feature injection
- Any comment in `nixosModules.kernelBazzite` explaining the `lib.makeOverridable` wrapper or the feature workaround
- Any comment explaining why `kernelWithFeatures` or `bazziteKernel` intermediate bindings are needed

**Replacement for `packages` output:** No comment needed (self-explanatory pass-through).  
**Replacement for `nixosModules.kernelBazzite`:** Same single-line comment as `hosts/vm.nix`.

---

## 8. Risks and Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| **Garnix/binary cache miss** — updated flake lock points to a new kernel rev not yet in cache; local build of the kernel takes 30–90 min | Medium | Run `nix flake update kernel-bazzite` first, then `sudo nixos-rebuild dry-build --flake .#vexos-vm` before switching; if build time is unacceptable, wait for Garnix CI to cache the new derivation |
| **New `linux-bazzite.nix` has different `kconfig` defaults** — `6.17.7-ba28` or newer may produce unexpected kernel behavior | Low | The upstream `pins.json` tracks a specific Bazzite kernel tag; `kernelPatches` are intentionally empty. Test VM build before switching physical hosts. |
| **`nix flake update kernel-bazzite` advances past `ce01769`** — if `main` has unverified commits, the fix may not be stable | Low | Check `vex-kernels` commit log after update; if the new head is unknown, pin to `ce01769ecf6bc51b80b8cc5ad1f51e6c394a3283` explicitly |
| **`flake.lock` diverges from other hosts** — AMD/NVIDIA hosts don't use the Bazzite kernel directly, but share the same `flake.lock` | None | `kernel-bazzite` input is only consumed by VM configs; AMD/NVIDIA host builds are unaffected by the lock update |
| **Removed `passthru.features` causes assertion failures at a different NixOS version** | Very Low | The new upstream `linux-bazzite.nix` appends `features` at the derivation top level; NixOS assertions on `ia32Emulation` and `efiBootStub` will be satisfied natively |
| **`modules/gpu/vm.nix` is changed in future to use a different priority** — `lib.mkOverride 49` may no longer win | Very Low | The existing comment on the `mkOverride 49` line documents the dependency on `vm.nix`'s priority; if `vm.nix` changes, this line must be updated in sync |

---

## 9. Validation

After implementation, run the following to confirm correctness:

```bash
# 1. Check flake evaluates cleanly
nix flake check

# 2. Dry-build the VM variant to confirm kernel resolves
sudo nixos-rebuild dry-build --flake .#vexos-vm

# 3. Confirm AMD and NVIDIA variants are unaffected
sudo nixos-rebuild dry-build --flake .#vexos-amd
sudo nixos-rebuild dry-build --flake .#vexos-nvidia

# 4. Apply to VM and verify running kernel
sudo nixos-rebuild switch --flake .#vexos-vm
uname -r
# Expected: 6.17.7-ba28 (or the version encoded in the updated pins.json), NOT 6.12.x
```

---

## 10. Dependencies

| Item | Value |
|---|---|
| `kernel-bazzite` target rev | `ce01769ecf6bc51b80b8cc5ad1f51e6c394a3283` (or latest `main`) |
| `vex-kernels` fix commit | `3b4182862015d45065f96ebc7b79d05cc2217784` |
| NixOS version | 25.05 |
| No new Nix-level dependencies | — workaround removed, no additions needed |
