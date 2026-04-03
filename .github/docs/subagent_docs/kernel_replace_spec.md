# Specification: Replace bazzite-kernel and cachyos-kernel with `pkgs.linuxPackages_latest`

**Feature:** kernel_replace  
**Date:** 2026-04-03  
**Status:** DRAFT  

---

## 1. Current State Analysis

### 1.1 System Variants

`flake.nix` defines four `nixosConfigurations` outputs:

| Variant | Host file | GPU module |
|---|---|---|
| `vexos-amd` | `hosts/amd.nix` | `modules/gpu/amd.nix` |
| `vexos-nvidia` | `hosts/nvidia.nix` | `modules/gpu/nvidia.nix` |
| `vexos-vm` | `hosts/vm.nix` | `modules/gpu/vm.nix` |
| `vexos-intel` | `hosts/intel.nix` | `modules/gpu/intel.nix` |

All four variants share `commonModules` (defined in `flake.nix`) which includes `cachyosOverlayModule`.

### 1.2 Kernel Currently Active Per Variant

| Variant | Effective kernel | Why |
|---|---|---|
| `vexos-amd` | CachyOS (via overlay) | `cachyosOverlayModule` patches `pkgs.linuxPackages_latest` to resolve to CachyOS; `modules/performance.nix` assigns `boot.kernelPackages = pkgs.linuxPackages_latest` |
| `vexos-nvidia` | CachyOS (via overlay) | Same as AMD |
| `vexos-intel` | CachyOS (via overlay) | Same as AMD |
| `vexos-vm` | Bazzite | `hosts/vm.nix` overrides with `lib.mkOverride 49 (pkgs.linuxPackagesFor inputs.kernel-bazzite.packages…)`, beating `modules/gpu/vm.nix` `lib.mkForce` (priority 50) |

### 1.3 Kernel-Related Occurrences — Complete Inventory

#### flake.nix

| Line(s) | What | Role |
|---|---|---|
| 25–32 | `nix-cachyos-kernel` flake input — `github:xddxdd/nix-cachyos-kernel/release` | Brings in CachyOS overlay |
| 34–41 | `kernel-bazzite` flake input — `github:VictoryTek/vex-kernels` | Brings in Bazzite kernel package |
| 51 | `outputs` destructuring: `…, nix-cachyos-kernel, …, kernel-bazzite, …` | Makes both available in outputs scope |
| 55–60 | `cachyosOverlayModule = { nixpkgs.overlays = [ nix-cachyos-kernel.overlays.pinned ]; }` | Inline module patching pkgs |
| 99 | `cachyosOverlayModule` listed in `commonModules` | Applied to ALL four variants |
| 106–119 | `packages.x86_64-linux.linux-bazzite = kernel-bazzite.packages…` | Garnix-cacheable package output (sole purpose: pre-build Bazzite for Garnix CI cache) |
| 172 | `nix-cachyos-kernel.overlays.pinned` inside `nixosModules.base` overlay list | CachyOS overlay in the exported module (used by `template/etc-nixos-flake.nix`) |
| 183–191 | `nixosModules.gpuVm` inline module: `boot.kernelPackages = lib.mkOverride 49 (pkgs.linuxPackagesFor kernel-bazzite…)` | Bazzite kernel for VM in exported nixosModule |

#### modules/performance.nix

| Line(s) | What | Role |
|---|---|---|
| 1–3 | Header comment mentions "zen kernel" | Stale/inaccurate; no code impact |
| 9 | `boot.kernelPackages = pkgs.linuxPackages_latest;` | Baseline kernel assignment — resolves to CachyOS when overlay is active; **already the correct final value** once overlay is stripped |
| 11 | Comment: "VM variant overrides this with the Bazzite kernel via lib.mkOverride 49" | Stale; needs update |

#### hosts/vm.nix

| Line(s) | What | Role |
|---|---|---|
| 4–11 | Header comment block documenting bazzite mkOverride 49 strategy | Documentation only |
| 22 | `{ pkgs, lib, inputs, ... }:` function args | `pkgs` and `lib` used only for Bazzite override |
| 29–35 | Bazzite `boot.kernelPackages = lib.mkOverride 49 (pkgs.linuxPackagesFor inputs.kernel-bazzite…)` | The Bazzite kernel override itself |

#### modules/gpu/vm.nix

| Line(s) | What | Role |
|---|---|---|
| 26 | `boot.kernelPackages = lib.mkForce pkgs.linuxPackages;` | LTS kernel baseline for VM; intermediate override priority 50 (overridden by hosts/vm.nix priority 49) |
| 27–28 | Comment: "hosts/vm.nix overrides this with the Bazzite kernel via lib.mkOverride 49" | Stale documentation |
| 29–38 | `nixpkgs.overlays` block with `makeModulesClosure allowMissing = true` | Workaround for Bazzite kernel missing `.ko` files (e.g. `pcips2`); **only needed for Bazzite** |

#### configuration.nix

| Line(s) | What | Role |
|---|---|---|
| 64 | `"https://cache.garnix.io"` substituter | Binary cache added solely for Bazzite (Garnix CI pre-builds `packages.x86_64-linux.linux-bazzite`) |
| 65 | `"https://attic.xuyh0120.win/lantian"` substituter | CachyOS kernel binary cache (xddxdd's attic) |
| 69 | `"cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="` trusted key | Garnix public key |
| 70 | `"lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc="` trusted key | CachyOS/lantian public key |

---

## 2. Problem Definition

The repository currently uses two non-standard, third-party kernels:

- **CachyOS kernel** (`nix-cachyos-kernel`): applied to AMD, NVIDIA, and Intel variants via an overlay that silently replaces `pkgs.linuxPackages_latest`. This couples every variant to an external, non-nixpkgs flake that cannot follow `nixpkgs` (by design per its CI). It adds a third-party binary cache (`attic.xuyh0120.win/lantian`) and an extra flake lock entry.

- **Bazzite kernel** (`kernel-bazzite` / `vex-kernels`): applied only to the VM variant. It requires a `makeModulesClosure` workaround overlay (missing modules), a Garnix CI package output, and its own binary cache entry. It also involves a complex priority override chain (`lib.mkOverride 49` vs `lib.mkForce` priority 50).

**Goal:** Replace both with `pkgs.linuxPackages_latest` (the standard NixOS latest stable kernel) across all variants. This kernel is well-tested, fully upstream, and ships all modules that NixOS expects — eliminating the need for third-party caches, overlays, and priority overrides.

---

## 3. Proposed Solution Architecture

### 3.1 Kernel After Change

All four variants will run `pkgs.linuxPackages_latest` from nixpkgs.

`modules/performance.nix` already sets `boot.kernelPackages = pkgs.linuxPackages_latest;` at normal NixOS module priority. Once the CachyOS overlay (`cachyosOverlayModule`) is removed from `commonModules`, this assignment will resolve to the stock nixpkgs latest kernel — no other change to module logic is required.

`modules/gpu/vm.nix` currently sets `boot.kernelPackages = lib.mkForce pkgs.linuxPackages;` (LTS) as an intermediate baseline. This line should be **removed**: the VM will inherit `pkgs.linuxPackages_latest` from `modules/performance.nix`, which is appropriate — mainline latest is fully supported in VM guests and VirtualBox/QEMU.

### 3.2 GPU Driver Compatibility

| GPU module | Kernel compatibility after change |
|---|---|
| `modules/gpu/amd.nix` | No conflict. `boot.initrd.kernelModules = [ "amdgpu" ]` and ROCm packages work with any upstream kernel. |
| `modules/gpu/nvidia.nix` | No conflict. The module references `config.boot.kernelPackages.nvidiaPackages.*` which resolves correctly from whatever `boot.kernelPackages` is set to — including `pkgs.linuxPackages_latest`. |
| `modules/gpu/intel.nix` | No conflict. `boot.initrd.kernelModules = [ "i915" ]` and Intel VPL/compute packages work with any upstream kernel. |
| `modules/gpu/vm.nix` | `makeModulesClosure` workaround can be removed entirely. The mainline kernel ships `pcips2` and all other standard modules. |

### 3.3 `nixosModules` Exported Module Impact

The `nixosModules.base` exported module (consumed by `template/etc-nixos-flake.nix`) includes the CachyOS overlay in its `nixpkgs.overlays` list. This overlay must be removed so external consumers also receive the stock kernel.

The `nixosModules.gpuVm` exported module contains the Bazzite kernel override inline. After removal it should simply reference `./modules/gpu/vm.nix` directly (same pattern as `gpuAmd`, `gpuNvidia`, `gpuIntel`).

---

## 4. Implementation Steps

### Step 1 — flake.nix: Remove `nix-cachyos-kernel` input

Remove lines 24–32 (the entire `nix-cachyos-kernel` input block including its comment).

### Step 2 — flake.nix: Remove `kernel-bazzite` input

Remove lines 34–41 (the entire `kernel-bazzite` input block including its comment).

### Step 3 — flake.nix: Update `outputs` destructuring

Update line 51 to remove `nix-cachyos-kernel` and `kernel-bazzite` from the argument set.

### Step 4 — flake.nix: Remove `cachyosOverlayModule`

Remove the `cachyosOverlayModule` definition (lines 55–60) and its entry in `commonModules` (line 99).

### Step 5 — flake.nix: Remove Garnix package output

Remove the entire `packages.x86_64-linux.linux-bazzite` block (lines 106–119, including its comment block).

### Step 6 — flake.nix: Clean `nixosModules.base`

Remove `nix-cachyos-kernel.overlays.pinned` from the `nixpkgs.overlays` list inside `nixosModules.base` (line 172).

### Step 7 — flake.nix: Simplify `nixosModules.gpuVm`

Replace the inline `gpuVm` module (which includes the Bazzite kernel override) with a direct file reference, matching the pattern of the other GPU module exports:

```nix
gpuVm = ./modules/gpu/vm.nix;
```

### Step 8 — configuration.nix: Remove third-party binary caches

From `nix.settings.substituters`, remove:
- `"https://cache.garnix.io"`
- `"https://attic.xuyh0120.win/lantian"`

From `nix.settings.trusted-public-keys`, remove:
- `"cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="`
- `"lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc="`

### Step 9 — hosts/vm.nix: Remove Bazzite kernel override

- Update header comment: remove Bazzite/mkOverride documentation.
- Change function args from `{ pkgs, lib, inputs, ... }:` to `{ inputs, ... }:` (`pkgs` and `lib` were only used for the Bazzite override; `inputs` is still needed for `inputs.up`).
- Remove the `boot.kernelPackages = lib.mkOverride 49 (…)` block and its comment.

### Step 10 — modules/gpu/vm.nix: Remove LTS kernel line and `makeModulesClosure` overlay

- Remove `boot.kernelPackages = lib.mkForce pkgs.linuxPackages;` and its comment block.
- Remove the entire `nixpkgs.overlays` block (the `makeModulesClosure allowMissing` workaround).
- Update function signature from `{ config, pkgs, lib, ... }:` to `{ config, lib, ... }:` since `pkgs` is no longer used.

### Step 11 — modules/performance.nix: Update stale comments

- Update the header comment on lines 2–3 to remove the "zen kernel" reference.
- Update the comment on line 11 to remove the Bazzite override reference.
- The actual `boot.kernelPackages = pkgs.linuxPackages_latest;` line is **already correct** and requires no change.

### Step 12 — flake.lock: Remove stale inputs

Run `nix flake lock --update-input nix-cachyos-kernel --update-input kernel-bazzite` or simply `nix flake update` followed by manual revert of other inputs if selective update is desired. Alternatively, after removing the inputs from `flake.nix`, run `nix flake lock` — Nix will automatically prune the orphaned entries from `flake.lock`.

---

## 5. Exact Diffs Per File

### 5.1 flake.nix

```diff
-    # CachyOS kernel — official NixOS packaging.
-    # `release` branch: CI-verified builds present in binary cache.
-    # CRITICAL: Do NOT add inputs.nixpkgs.follows here.
-    # The version pinning between CachyOS patches and kernel source is managed
-    # internally by the release branch CI. Adding nixpkgs.follows breaks this.
-    nix-cachyos-kernel = {
-      url = "github:xddxdd/nix-cachyos-kernel/release";
-    };
-
-    # Bazzite kernel — gaming and handheld optimized kernel for VM testing.
-    # CRITICAL: Do NOT add inputs.nixpkgs.follows = "nixpkgs" here.
-    # vex-kernels pins nixos-unstable internally; the nixosModule evaluates
-    # pkgs from the host system, but the flake may require unstable tooling
-    # for standalone builds. Mirrors the established precedent for
-    # nix-cachyos-kernel. A separate nixpkgs lock entry is acceptable.
-    kernel-bazzite = {
-      url = "github:VictoryTek/vex-kernels";
-    };
-
```

```diff
-  outputs = { self, nixpkgs, nixpkgs-unstable, nix-gaming, nix-cachyos-kernel, home-manager, kernel-bazzite, ... }@inputs:
+  outputs = { self, nixpkgs, nixpkgs-unstable, nix-gaming, home-manager, ... }@inputs:
```

```diff
-    # Inline NixOS module that applies the CachyOS kernel overlay.
-    # Using a closure here (capturing nix-cachyos-kernel from the outputs scope)
-    # so the overlay works when nixosModules.base is consumed by external flakes
-    # (template/etc-nixos-flake.nix) without needing specialArgs.
-    cachyosOverlayModule = {
-      nixpkgs.overlays = [ nix-cachyos-kernel.overlays.pinned ];
-    };
-
```

```diff
     commonModules = [
       /etc/nixos/hardware-configuration.nix
       nix-gaming.nixosModules.pipewireLowLatency
-      cachyosOverlayModule
       unstableOverlayModule
       homeManagerModule
     ];
```

```diff
-    # ── Garnix-cacheable package outputs ─────────────────────────────────────
-    # The nixosConfigurations all import /etc/nixos/hardware-configuration.nix
-    # which doesn't exist on Garnix's servers, so they can never be evaluated
-    # there.  Exposing the Bazzite kernel as a plain package gives Garnix
-    # something it CAN build — Garnix's default config covers *.x86_64-linux.*
-    # — so the compiled kernel lands in cache.garnix.io and future rebuilds on
-    # the VM fetch it instead of compiling it locally.
-    #
-    # IMPORTANT: reference kernel-bazzite.packages directly (NOT callPackage)
-    # so this output has the same .drv hash as what hosts/vm.nix uses.
-    # Using callPackage here with vexos-nix's nixpkgs would produce a different
-    # toolchain than vex-kernels' own pinned nixpkgs, yielding a different store
-    # path that Garnix would cache but nixos-rebuild would never request.
-    packages.x86_64-linux.linux-bazzite =
-      kernel-bazzite.packages.x86_64-linux.linux-bazzite;
-
```

```diff
       nixosModules = {
         base = { ... }: {
           imports = [ … ];
           nixpkgs.overlays = [
-            nix-cachyos-kernel.overlays.pinned
             (final: prev: {
               unstable = import nixpkgs-unstable { … };
             })
           ];
         };
```

```diff
-      gpuVm = { pkgs, lib, ... }: {
-        imports = [ ./modules/gpu/vm.nix ];
-        # Bazzite kernel: mkOverride 49 beats modules/gpu/vm.nix lib.mkForce (priority 50).
-        boot.kernelPackages = lib.mkOverride 49 (
-          pkgs.linuxPackagesFor kernel-bazzite.packages.x86_64-linux.linux-bazzite
-        );
-      };
+      gpuVm     = ./modules/gpu/vm.nix;
```

### 5.2 configuration.nix

```diff
     substituters = [
       "https://cache.nixos.org"          # Official NixOS cache — always required
-      "https://cache.garnix.io"          # Garnix CI cache
-      "https://attic.xuyh0120.win/lantian" # CachyOS kernel binary cache
     ];
     trusted-public-keys = [
       "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
-      "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
-      "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc="
     ];
```

### 5.3 hosts/vm.nix

```diff
-# hosts/vm.nix
-# vexos — Virtual machine guest build (QEMU/KVM + VirtualBox).
-# Rebuild: sudo nixos-rebuild switch --flake .#vexos-vm
-#
-# Bazzite kernel: applied here for testing purposes only.
-# lib.mkOverride 49 is required to override both:
-#   - modules/performance.nix (normal priority, CachyOS kernel)
-#   - modules/gpu/vm.nix (lib.mkForce / priority 50, LTS kernel)
-# Priority 49 < 50, so this definition wins cleanly without a conflict.
-#
+# hosts/vm.nix
+# vexos — Virtual machine guest build (QEMU/KVM + VirtualBox).
+# Rebuild: sudo nixos-rebuild switch --flake .#vexos-vm
+#
 # Bootloader: NOT configured here — set it in your host's hardware-configuration.nix.
```

```diff
-{ pkgs, lib, inputs, ... }:
+{ inputs, ... }:
```

```diff
-  # Bazzite kernel — overrides modules/gpu/vm.nix LTS (lib.mkForce/priority 50) and
-  # modules/performance.nix CachyOS setting (normal priority).
-  # mkOverride 49 wins over modules/gpu/vm.nix which uses mkForce (priority 50).
-  #
-  # References inputs.kernel-bazzite.packages directly so the store path matches
-  # exactly what Garnix CI built and cached from the vex-kernels repo.  Re-deriving
-  # via pkgs.callPackage would use vexos-nix's nixos-25.11 pkgs instead of
-  # vex-kernels' nixos-unstable pkgs, producing a different store path and a
-  # guaranteed cache miss on every rebuild.
-  boot.kernelPackages = lib.mkOverride 49 (
-    pkgs.linuxPackagesFor inputs.kernel-bazzite.packages.x86_64-linux.linux-bazzite
-  );
-
```

### 5.4 modules/gpu/vm.nix

```diff
-{ config, pkgs, lib, ... }:
+{ config, lib, ... }:
```

```diff
-  # LTS kernel baseline — provides a clean build for VirtualBox GuestAdditions
-  # and avoids zen/CachyOS overhead in a VM environment.
-  # hosts/vm.nix overrides this with the Bazzite kernel via lib.mkOverride 49.
-  boot.kernelPackages = lib.mkForce pkgs.linuxPackages;
-
-  # The Bazzite kernel (Fedora gaming config) does not ship every module that
-  # nixos-generate-config may list in hardware-configuration.nix.  The known
-  # offender is pcips2 (PCI-attached PS/2 controller), which is absent as a
-  # loadable .ko in Bazzite/Fedora kernels.  Patching makeModulesClosure to
-  # tolerate missing modules prevents a fatal build failure when such modules
-  # appear in boot.initrd.availableKernelModules.
-  nixpkgs.overlays = [
-    (final: prev: {
-      makeModulesClosure = args:
-        prev.makeModulesClosure (args // { allowMissing = true; });
-    })
-  ];
-
```

### 5.5 modules/performance.nix (comment updates only)

```diff
-# modules/performance.nix
-# Gaming-grade kernel and performance tuning: zen kernel, kernel params,
-# ZRAM swap, CPU governor, BBR TCP, VM tunables, transparent huge pages.
+# modules/performance.nix
+# Gaming-grade kernel and performance tuning: latest kernel, kernel params,
+# ZRAM swap, CPU governor, BBR TCP, VM tunables, transparent huge pages.
```

```diff
-  # Standard latest kernel: tracks the most recent stable upstream release.
-  # Provided by nixpkgs as pkgs.linuxPackages_latest.
-  # VM variant (hosts/vm.nix) overrides this with the Bazzite kernel via lib.mkOverride 49.
+  # Standard latest kernel: tracks the most recent stable upstream release.
+  # Provided by nixpkgs as pkgs.linuxPackages_latest (no third-party overlay).
   boot.kernelPackages = pkgs.linuxPackages_latest;
```

---

## 6. Dependencies

No new dependencies are introduced. All removals:

| Removed | Type | Was used for |
|---|---|---|
| `nix-cachyos-kernel` flake input | External flake | CachyOS kernel overlay |
| `kernel-bazzite` flake input | External flake | Bazzite kernel package |
| `https://attic.xuyh0120.win/lantian` | Binary cache substituter | CachyOS kernel pre-built binaries |
| `https://cache.garnix.io` | Binary cache substituter | Bazzite kernel pre-built binaries (Garnix CI) |

`pkgs.linuxPackages_latest` is already present in nixpkgs — no new flake input is needed.

---

## 7. Risk Assessment

| Risk | Severity | Mitigation |
|---|---|---|
| The stock `pkgs.linuxPackages_latest` may not include a niche kernel module that was present in CachyOS | Low | CachyOS applies performance patches on top of the upstream kernel; it does not add new loadable modules absent from mainline. All hardware support (amdgpu, i915, nvidia, virtio_gpu, qxl) is present in mainline. |
| NVIDIA driver package selection uses `config.boot.kernelPackages.nvidiaPackages.*` | None | This attribute traversal works identically with `pkgs.linuxPackages_latest` — nixpkgs exposes `nvidiaPackages` on every kernel packages set. |
| `makeModulesClosure` overlay removal may expose missing-module failures | Low | The overlay was added strictly for Bazzite (which uses Fedora's kernel config and omits some modules NixOS expects). Mainline kernel ships all standard modules including `pcips2`. |
| Removing `cache.garnix.io` means Garnix CI no longer has a purpose in this repo | None | The `packages.x86_64-linux.linux-bazzite` output was the only Garnix-cacheable thing. After removal there is nothing for Garnix to build. |
| `nix flake lock` will retain stale entries for removed inputs until pruned | Low | Run `nix flake lock` after editing `flake.nix`; Nix automatically removes entries for inputs no longer referenced. |
| CachyOS `sched_ext` / `scx_lavd` scheduler noted as commented-out in `modules/performance.nix` | None | Already commented out and noted as requiring kernel/package confirmation. `pkgs.linuxPackages_latest` includes `sched_ext` support in 6.12+. No action needed. |

---

## 8. Files to Modify

| File | Change type |
|---|---|
| `flake.nix` | Remove 2 flake inputs, remove CachyOS overlay module, remove Garnix package output, update `nixosModules` |
| `configuration.nix` | Remove 2 substituters + 2 trusted public keys |
| `hosts/vm.nix` | Remove Bazzite kernel override block, update header comment, simplify function args |
| `modules/gpu/vm.nix` | Remove `boot.kernelPackages` line, remove `makeModulesClosure` overlay, update function signature |
| `modules/performance.nix` | Comment-only updates (no logic changes) |

## 9. Files NOT to Modify

| File | Reason |
|---|---|
| `hosts/amd.nix` | No kernel references; no change needed |
| `hosts/nvidia.nix` | No kernel references; no change needed |
| `hosts/intel.nix` | No kernel references; no change needed |
| `modules/gpu/amd.nix` | No kernel-package references; works with any upstream kernel |
| `modules/gpu/nvidia.nix` | Uses `config.boot.kernelPackages.nvidiaPackages.*`; works with any kernel |
| `modules/gpu/intel.nix` | No kernel-package references |
| `modules/packages.nix` | No kernel references |
| `template/etc-nixos-flake.nix` | Consumes `nixosModules.gpuVm`; after simplification in flake.nix it simply points to `modules/gpu/vm.nix` — no external API change |
| `scripts/preflight.sh` | No kernel-specific checks; existing dry-build loop covers all variants |

---

*Spec written by: Research Subagent*  
*Spec path: `.github/docs/subagent_docs/kernel_replace_spec.md`*
