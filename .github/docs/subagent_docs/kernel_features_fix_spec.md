# Spec: Fix `features` Argument Error for Bazzite Kernel

**Feature name:** `kernel_features_fix`
**Date:** 2026-03-29
**Status:** Ready for Implementation

---

## 1. Current State Analysis

### Repository files referencing the Bazzite kernel

| File | Role |
|------|------|
| `flake.nix` (inputs) | Declares `kernel-bazzite` flake input from `github:VictoryTek/vex-kernels` |
| `flake.nix` (`packages.x86_64-linux.linux-bazzite`) | Exposes kernel derivation for Garnix CI caching via `nixpkgs.legacyPackages.x86_64-linux.callPackage "${kernel-bazzite}/pkgs/linux-bazzite.nix" {}` |
| `flake.nix` (`nixosModules.kernelBazzite`) | NixOS module that sets `boot.kernelPackages = lib.mkOverride 49 (pkgs.linuxPackagesFor kernel-bazzite.packages.x86_64-linux.linux-bazzite)` |
| `hosts/vm.nix` | Sets `boot.kernelPackages = lib.mkOverride 49 (pkgs.linuxPackagesFor inputs.kernel-bazzite.packages.x86_64-linux.linux-bazzite)` |
| `modules/gpu/vm.nix` | Sets `boot.kernelPackages = lib.mkForce pkgs.linuxPackages` (overridden by `hosts/vm.nix`) |
| `modules/performance.nix` | Sets `boot.kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-bore` (AMD/NVIDIA builds) |

### Locked vex-kernels revision

```
rev:  d612bf2871f1b7e21a6acf13a8a359e655edefec
narHash: sha256-mjKQSWl0uwQc9aDCCeTU5245n8UIUCPCzBE+oRRf2bE=
store path: /nix/store/1w7g0r9g8cr1cdh96lva0lspzlsayhn5-source
```

### Current `linux-bazzite.nix` function signature (locked rev)

```nix
# /nix/store/1w7g0r9g8cr1cdh96lva0lspzlsayhn5-source/pkgs/linux-bazzite.nix
{
  lib,
  fetchFromGitHub,
  fetchurl,
  linuxManualConfig,
  runCommand,
}:
# ... uses linuxManualConfig + kernel.overrideAttrs
# Does NOT declare: features, randstructSeed, kernelPatches
# Does NOT end with // { features = ...; passthru = ...; }
```

The function is strict (no `...` catch-all). It accepts exactly 5 args and sets no `passthru.features`.

### vex-kernels flake.nix package definition

```nix
packages.${system} = {
  linux-bazzite = pkgs.callPackage ./pkgs/linux-bazzite.nix {};
  # pkgs here = nixpkgs-unstable
};
```

`pkgs.callPackage` wraps the function in `lib.makeOverridable`, preserving a reference to the original 5-arg function.

---

## 2. Problem Definition

### Root Cause

NixOS nixpkgs revision `4590696c8693fea477850fe379a01544293ca4e2` (the `nixos-25.11` channel pinned in `flake.lock`) contains `nixos/modules/system/boot/kernel.nix` with the following `apply` function on the `boot.kernelPackages` option:

```nix
# nixos/modules/system/boot/kernel.nix:67
apply =
  kernelPackages:
  kernelPackages.extend (
    self: super: {
      kernel = super.kernel.override (originalArgs: {
        inherit randstructSeed;
        kernelPatches = (originalArgs.kernelPatches or [ ]) ++ kernelPatches;
        features = lib.recursiveUpdate super.kernel.features features;  # ← needs passthru.features
      });
    }
  );
```

This `apply` function is **always evaluated** when any `nixosConfiguration` sets `boot.kernelPackages`, including `vexos-vm`.

### Two-part failure

#### Failure A — "unexpected argument 'features'"

Call chain:

1. `hosts/vm.nix` sets `boot.kernelPackages = lib.mkOverride 49 (pkgs.linuxPackagesFor inputs.kernel-bazzite.packages.x86_64-linux.linux-bazzite)`
2. NixOS's `apply` function runs `kernelPackages.extend (self: super: { kernel = super.kernel.override (origArgs: { ..., features }) })`
3. `super.kernel` is `inputs.kernel-bazzite.packages.x86_64-linux.linux-bazzite` — a `makeOverridable`-wrapped derivation whose underlying function is the 5-arg `linux-bazzite.nix` function
4. `.override (origArgs: { ..., features = ... })` computes `newArgs = origArgs // { randstructSeed; kernelPatches; features }` and calls the original function with those merged args
5. The original `linux-bazzite.nix` function is called with 8 args (the original 5 + 3 new ones)
6. **ERROR**: `"function 'anonymous lambda' called with unexpected argument 'features'"` at `linux-bazzite.nix:1:1`

#### Failure B — `super.kernel.features` attribute missing

Even if Failure A is patched, `lib.recursiveUpdate super.kernel.features features` accesses `super.kernel.features`. Since `linux-bazzite.nix` does not set `passthru.features`, this attribute is absent on the derivation and would throw `"attribute 'features' missing"`.

### Confirmed reproduction

```
error: function 'anonymous lambda' called with unexpected argument 'features'
  at /nix/store/1w7g0r9g8cr1cdh96lva0lspzlsayhn5-source/pkgs/linux-bazzite.nix:1:1:
       1| {
          | ^
       2|   lib,
```

Reproduced via:
```
nix eval --impure \
  ".#nixosConfigurations.vexos-vm.config.boot.kernelPackages.kernel.version"
```

### Why the standard kernels are unaffected

Standard nixpkgs kernels (defined via `pkgs/os-specific/linux/kernel/generic.nix`) explicitly declare:

```nix
{
  # ... other args ...
  features ? { },
  randstructSeed ? "",
  kernelPatches ? [ ],
  ...
}@args:
```

They have `features ? {}` in their signature AND a `...` catch-all. `linux-bazzite.nix` has neither.

### Scope

Only `nixosConfigurations.vexos-vm` (and by extension `nixosModules.kernelBazzite`) is affected. `vexos-amd`, `vexos-nvidia`, and `vexos-intel` use the CachyOS kernel which goes through `generic.nix` and is unaffected.

---

## 3. Proposed Solution

### Approach

**Option A (RECOMMENDED) — `overrideAttrs` + `lib.makeOverridable` shim**

Verified empirically: `rawKernel.overrideAttrs (old: { passthru = ...; })` where ONLY `passthru` changes produces the **identical `.drv` store path** as `rawKernel`:

```
raw:          /nix/store/jq67g854z20awhwh8y43bq7qmnbzgrf6-linux-6.17.7-ba28.drv
withFeatures: /nix/store/jq67g854z20awhwh8y43bq7qmnbzgrf6-linux-6.17.7-ba28.drv
```

This means Option A **preserves the Garnix cache** — the kernel binary built by Garnix CI from the vex-kernels repo will still be fetched rather than compiled locally.

The wrapper uses `lib.makeOverridable` to create a new `override`-able function that:
- Accepts `features ? {}`, `randstructSeed ? ""`, `kernelPatches ? []`, and `...` to absorb any future additions
- Always returns `kernelWithFeatures` (the correctly annotated derivation)
- Provides `passthru.features` so `lib.recursiveUpdate super.kernel.features features` evaluates correctly

```nix
let
  rawKernel = inputs.kernel-bazzite.packages.x86_64-linux.linux-bazzite;
  kernelWithFeatures = rawKernel.overrideAttrs (old: {
    passthru = (old.passthru or {}) // {
      features = {
        ia32Emulation = true;  # CONFIG_IA32_EMULATION=y in Fedora gaming config
        efiBootStub   = true;  # CONFIG_EFI_STUB=y     in Fedora gaming config
      };
    };
  });
  bazziteKernel = lib.makeOverridable
    ({ features ? {}, randstructSeed ? "", kernelPatches ? [], ... }:
      kernelWithFeatures)
    {};
in
pkgs.linuxPackagesFor bazziteKernel
```

**Option B — local `callPackage` wrapper**

Re-derive the kernel through vexos-nix's own pkgs with a wrapper function that adds `features ? {}` and `...`. Simpler code but **loses the Garnix cache** (different nixpkgs toolchain = different store path):

```nix
pkgs.linuxPackagesFor (
  pkgs.callPackage (
    { lib, fetchFromGitHub, fetchurl, linuxManualConfig, runCommand
    , features ? {}, randstructSeed ? "", kernelPatches ? [], ... }:
    let
      inner = (import "${inputs.kernel-bazzite}/pkgs/linux-bazzite.nix") {
        inherit lib fetchFromGitHub fetchurl linuxManualConfig runCommand;
      };
    in
    inner.overrideAttrs (old: {
      passthru = (old.passthru or {}) // {
        features = { ia32Emulation = true; efiBootStub = true; };
      };
    })
  ) {}
)
```

**Option A is chosen** because:
- Same store path as Garnix-built kernel — cache hit, no local compile
- Fixes both failure modes (function signature + passthru.features)
- Clean separation between "add metadata" and "absorb NixOS override args"
- `lib.makeOverridable` is the standard NixOS pattern for wrappable kernel shims

---

## 4. Implementation Steps

### Step 1 — Update `hosts/vm.nix`

**Location:** `hosts/vm.nix`, the `boot.kernelPackages` assignment (currently lines 50–53)

**Current code:**
```nix
boot.kernelPackages = lib.mkOverride 49 (
  pkgs.linuxPackagesFor
    inputs.kernel-bazzite.packages.x86_64-linux.linux-bazzite
);
```

**Replace with:**
```nix
boot.kernelPackages = lib.mkOverride 49 (
  let
    # linux-bazzite.nix (vex-kernels, locked rev d612bf28) does not declare
    # `features`, `randstructSeed`, or `kernelPatches` in its function
    # signature, and does not set passthru.features.  NixOS nixpkgs 25.11
    # kernel.nix always calls kernel.override { features; randstructSeed;
    # kernelPatches } — see nixos/modules/system/boot/kernel.nix:67.
    #
    # Fix part 1: add passthru.features so lib.recursiveUpdate
    #   super.kernel.features features does not throw "attribute missing".
    #   overrideAttrs with passthru-only changes preserves the .drv store
    #   path, so Garnix-cached builds are still used.
    #
    # Fix part 2: wrap with lib.makeOverridable using a function that accepts
    #   features/randstructSeed/kernelPatches via `...`, so the .override
    #   call does not reach the strict 5-arg linux-bazzite.nix function.
    rawKernel = inputs.kernel-bazzite.packages.x86_64-linux.linux-bazzite;
    kernelWithFeatures = rawKernel.overrideAttrs (old: {
      passthru = (old.passthru or {}) // {
        features = {
          ia32Emulation = true;  # CONFIG_IA32_EMULATION=y — Fedora gaming config
          efiBootStub   = true;  # CONFIG_EFI_STUB=y       — Fedora gaming config
        };
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

**Also update the comments** at the top of `hosts/vm.nix` that currently state:
```
# features (ia32Emulation, efiBootStub) are now exposed by linux-bazzite.nix
# itself via the `// { features = ... }` at the end of that file.
```
Replace with:
```
# features (ia32Emulation, efiBootStub) are added via overrideAttrs because
# linux-bazzite.nix (locked rev d612bf28) does not set passthru.features.
# The lib.makeOverridable wrapper absorbs the NixOS kernel.nix override args
# (features, randstructSeed, kernelPatches) without forwarding them upstream.
```

**Also remove stale comments** at lines 9–18 that reference `lib.mkOverride 49` detail about priorities, `features.ia32Emulation`, and `features.efiBootStub` being "declared inside the callPackage wrapper" — these were written for an older approach.

### Step 2 — Update `flake.nix` nixosModules.kernelBazzite

**Location:** `flake.nix`, the `kernelBazzite` module definition (currently the last block of `nixosModules`)

**Current code:**
```nix
kernelBazzite = { pkgs, lib, ... }: {
  boot.kernelPackages = lib.mkOverride 49 (
    pkgs.linuxPackagesFor
      kernel-bazzite.packages.x86_64-linux.linux-bazzite
  );
};
```

**Replace with:**
```nix
kernelBazzite = { pkgs, lib, ... }: {
  boot.kernelPackages = lib.mkOverride 49 (
    let
      rawKernel = kernel-bazzite.packages.x86_64-linux.linux-bazzite;
      kernelWithFeatures = rawKernel.overrideAttrs (old: {
        passthru = (old.passthru or {}) // {
          features = {
            ia32Emulation = true;
            efiBootStub   = true;
          };
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

**Also update the comment block** above `kernelBazzite` that currently says "linux-bazzite.nix now exposes `features` natively so no wrapper is needed" — this is incorrect; replace it with:
```nix
# Bazzite kernel override for the VM variant (consumed via template/etc-nixos-flake.nix).
# Uses lib.mkOverride 49 to beat modules/gpu/vm.nix lib.mkForce (priority 50).
# Wraps rawKernel with passthru.features and lib.makeOverridable shim to satisfy
# NixOS nixpkgs 25.11 kernel.nix override requirements (see kernel_features_fix_spec.md).
```

### Step 3 — (Optional) Update `flake.nix` `packages.x86_64-linux.linux-bazzite`

This package is exposed for Garnix CI caching of the raw kernel derivation. It is not currently broken (it is not evaluated through `boot.kernelPackages`). However, adding `passthru.features` to it improves consistency and makes it usable as a kernel derivation if ever referenced directly:

**Current code:**
```nix
packages.x86_64-linux.linux-bazzite =
  nixpkgs.legacyPackages.x86_64-linux.callPackage
    "${kernel-bazzite}/pkgs/linux-bazzite.nix" {};
```

**Optional replacement:**
```nix
packages.x86_64-linux.linux-bazzite =
  (nixpkgs.legacyPackages.x86_64-linux.callPackage
    "${kernel-bazzite}/pkgs/linux-bazzite.nix" {})
  .overrideAttrs (old: {
    passthru = (old.passthru or {}) // {
      features = { ia32Emulation = true; efiBootStub = true; };
    };
  });
```

This is **non-breaking** and does NOT affect the store path of the Garnix-cached derivation (verified: `overrideAttrs` with passthru-only changes produces the same `.drv`).

---

## 5. Dependencies

- No new flake inputs required
- No new packages required
- `lib.makeOverridable` and `overrideAttrs` are both standard nixpkgs/nixlib primitives (stable API, no version concern)
- `passthru.features` values (`ia32Emulation`, `efiBootStub`) match the Fedora gaming kernel config that Bazzite uses (Bazzite kernel config enables `CONFIG_IA32_EMULATION=y` and `CONFIG_EFI_STUB=y`)

---

## 6. Configuration Changes

None. `system.stateVersion` is not affected. No new NixOS options, no new overlays, no new packages.

---

## 7. Risks and Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| `passthru.features` values are wrong (e.g., `ia32Emulation = false`) | Medium | Both values are confirmed present in Bazzite's Fedora gaming config. The comment in the old `hosts/vm.nix` code already declared them. Additionally, wrong values would cause NixOS assertion failures (not silent errors) during evaluation, making them easy to detect. |
| `overrideAttrs` with passthru changes hypothetically affecting store path in a future nixpkgs version | Low | Empirically verified to produce identical `.drv` paths with the locked nixpkgs rev. If future nixpkgs changes this behavior, the result is a cache miss (not a breakage). |
| `lib.makeOverridable` shim swallowing `kernelPatches` from NixOS modules | Low | vexos-nix's modules do not set `boot.kernelPatches`. If needed in future, the shim can be updated to apply patches via `kernelWithFeatures.overrideAttrs (old: { patches = old.patches ++ kernelPatches; })` inside the lambda. |
| `linux-bazzite.nix` upstream adding `features ? {}` natively in a future vex-kernels commit | None | If the upstream adds it, our wrapper becomes a safe no-op. The `overrideAttrs` passthru addition is still correct and harmless. |
| Upstream vex-kernels `nixosModules.default` has the same bug | Out of scope | That module uses `lib.mkDefault` rather than `lib.mkOverride 49`, so it is overridden by our `hosts/vm.nix` definition and never evaluated. |

---

## 8. Validation Plan

After implementation, run:

```bash
# 1. Quick evaluation check — must not error
nix eval --impure ".#nixosConfigurations.vexos-vm.config.boot.kernelPackages.kernel.version"

# 2. Verify features passthru
nix eval --impure ".#nixosConfigurations.vexos-vm.config.boot.kernelPackages.kernel.passthru.features"
# Expected: { efiBootStub = true; ia32Emulation = true; }

# 3. Full preflight
bash scripts/preflight.sh
```

---

## 9. Files to Modify

| File | Change |
|------|--------|
| `hosts/vm.nix` | Replace `boot.kernelPackages` with wrapped version; update comments |
| `flake.nix` | Replace `nixosModules.kernelBazzite` definition; update stale comments; optionally add `passthru.features` to `packages.x86_64-linux.linux-bazzite` |
