# Specification: Bazzite Kernel Integration for `vexos-vm`

**Feature:** `bazzite_kernel_vm`
**Scope:** VM variant only (`vexos-vm`) — testing purposes
**Date:** 2026-03-28
**Status:** Draft

---

## 1. Current State Analysis

### 1.1 Flake Structure (`flake.nix`)

| Attribute | Value |
|-----------|-------|
| `nixpkgs` | `github:NixOS/nixpkgs/nixos-25.11` |
| `nixpkgs-unstable` | `github:NixOS/nixpkgs/nixos-unstable` (no `follows` — intentional) |
| `nix-gaming` | `github:fufexan/nix-gaming` with `inputs.nixpkgs.follows = "nixpkgs"` |
| `home-manager` | `github:nix-community/home-manager/release-25.11` with `inputs.nixpkgs.follows = "nixpkgs"` |
| `nix-cachyos-kernel` | `github:xddxdd/nix-cachyos-kernel/release` (NO `follows` — intentional, documented) |

**Outputs:** `vexos-amd`, `vexos-nvidia`, `vexos-vm`, `vexos-intel`

**`commonModules`** (applied to ALL four outputs):
```nix
commonModules = [
  /etc/nixos/hardware-configuration.nix
  nix-gaming.nixosModules.pipewireLowLatency
  cachyosOverlayModule     # adds pkgs.cachyosKernels.*
  unstableOverlayModule    # adds pkgs.unstable.*
  homeManagerModule
];
```

**`nixConfig`** in `flake.nix` currently includes:
```nix
nixConfig = {
  extra-substituters = [
    "https://attic.xuyh0120.win/lantian"
    "https://cache.garnix.io"
  ];
  extra-trusted-public-keys = [
    "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc="
    "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
  ];
};
```

### 1.2 Kernel Selection Chain for `vexos-vm`

The kernel option `boot.kernelPackages` is set in three places relevant to the VM output, resolved by NixOS priority merge rules (lower number = higher precedence):

| Module | Setting | Priority |
|--------|---------|----------|
| `modules/performance.nix` | `pkgs.cachyosKernels.linuxPackages-cachyos-bore` | 100 (normal) |
| `modules/gpu/vm.nix` | `lib.mkForce pkgs.linuxPackages` | 50 (`mkForce`) |
| *(bazzite module, after integration)* | `lib.mkDefault (pkgs.linuxPackagesFor ...)` | 1000 (`mkDefault`) |

**Current result for `vexos-vm`:** LTS kernel (`pkgs.linuxPackages`) — the `lib.mkForce` in `modules/gpu/vm.nix` wins.

**Key comment in `modules/gpu/vm.nix`:** *"zen kernel doesn't build VirtualBox GuestAdditions cleanly; use LTS instead."* The `lib.mkForce` explicitly prevents any higher-priority (lower-number) module from changing the kernel for the VM.

**Critical implication:** The bazzite module (sourced from `vex-kernels`) uses `lib.mkDefault` (priority 1000). If simply imported, it would be defeated by both `modules/performance.nix` (priority 100) and `modules/gpu/vm.nix` (priority 50). A `lib.mkForce` is required in `hosts/vm.nix` to elect the bazzite kernel.

### 1.3 `hosts/vm.nix` — Current State

```nix
{ ... }:
{
  imports = [
    ../configuration.nix
    ../modules/gpu/vm.nix
  ];
  networking.hostName = "vexos-vm";
}
```

The module header accepts no typed arguments (uses `{ ... }`). It must be expanded to receive `inputs`, `pkgs`, and `lib`.

### 1.4 `modules/gpu/vm.nix` — Current State

Key settings:
- `services.qemuGuest.enable = true`
- `services.spice-vdagentd.enable = true`
- `virtualisation.virtualbox.guest.enable = true`
- `boot.initrd.kernelModules = [ "virtio_gpu" ]`
- `boot.kernelModules = [ "qxl" ]`
- `powerManagement.cpuFreqGovernor = lib.mkForce "performance"`
- `boot.kernelPackages = lib.mkForce pkgs.linuxPackages` ← LTS override

### 1.5 `vex-kernels` Flake — Upstream Analysis

Source: `github:VictoryTek/vex-kernels`

**`flake.nix` (upstream):**
```nix
inputs = {
  nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
};

nixosModules.default = { pkgs, lib, ... }: {
  boot.kernelPackages = lib.mkDefault (
    pkgs.linuxPackagesFor (pkgs.callPackage ./pkgs/linux-bazzite.nix {})
  );
};
```

**Key findings:**
1. The upstream flake pins its own nixpkgs to `nixos-unstable`.
2. `nixosModules.default` only sets `boot.kernelPackages` — nothing else.
3. The `pkgs` argument in the module is supplied by the **host NixOS system** (in this case, `nixos-25.11`), not by the flake's own nixpkgs.
4. The kernel derivation (`pkgs/linux-bazzite.nix`) uses `linuxManualConfig`, `fetchFromGitHub`, `fetchurl`, and `runCommand` — all standard nixpkgs functions available in both stable and unstable channels.
5. Current tracked kernel version: **6.17.7-ba28** (Bazzite gaming/handheld-optimized kernel).
6. License: **GPL-2.0**.

---

## 2. Problem Definition

The `vexos-vm` NixOS output currently runs the LTS kernel (`pkgs.linuxPackages`) because `modules/gpu/vm.nix` forces it. The goal is to run the Bazzite kernel in `vexos-vm` for testing purposes, without affecting the `vexos-amd`, `vexos-nvidia`, or `vexos-intel` outputs.

Specific challenges:
- The bazzite module uses a low-priority `lib.mkDefault` which is defeated by existing `lib.mkForce` and normal-priority settings.
- The `kernel-bazzite` binary cache (`vex-kernels.cachix.org`) must be available at build time and in the deployed system.
- VirtualBox GuestAdditions are compiled against the running kernel; a custom kernel may or may not build them cleanly.
- The new flake input must follow project conventions (documented `nixpkgs.follows` decision, `nixpkgs.follows` omitted where the upstream deliberately pins an independent nixpkgs).

---

## 3. Research Findings

### Source 1 — `vex-kernels` upstream `flake.nix` (direct code inspection)
URL: `https://github.com/VictoryTek/vex-kernels/blob/main/flake.nix`

The `nixosModules.default` is a single-option module setting only `boot.kernelPackages` via `lib.mkDefault`. The host's `pkgs` is used for `callPackage`, not the flake's internal nixpkgs. This means the kernel is cross-evaluated with the host channel (nixos-25.11) for all build infrastructure, while the kernel source and patches are fetched from upstream via `pins.json`.

### Source 2 — NixOS Wiki: Linux Kernel
URL: `https://wiki.nixos.org/wiki/Linux_kernel`

`boot.kernelPackages` accepts a `linuxPackagesFor`-style package set. Multiple modules setting the same option are resolved by NixOS priority rules: `lib.mkForce` (50) > normal (100) > `lib.mkDefault` (1000). To override an existing `lib.mkForce`, a consumer must also use `lib.mkForce` or `lib.mkOverride ≤ 50`.

### Source 3 — NixOS Wiki: Flakes (Input Schema / `nixpkgs.follows`)
URL: `https://wiki.nixos.org/wiki/Flakes`

`inputs.<name>.inputs.nixpkgs.follows = "nixpkgs"` makes a transitive dependency reuse the parent flake's nixpkgs instance. This avoids a duplicate nixpkgs in `flake.lock` and reduces store usage. However, it is only safe when the transitive flake does not depend on features specific to a different nixpkgs channel. Upstream kernel flakes that target `nixos-unstable` may rely on newer build infrastructure; the decision must be evaluated per-flake.

### Source 4 — NixOS `flake.nix` / `nixConfig` binary cache pattern
URL: `https://wiki.nixos.org/wiki/Flakes#Nix_configuration`

`nixConfig.extra-substituters` and `nixConfig.extra-trusted-public-keys` in `flake.nix` configure binary caches **for the flake consumer** during evaluation and build (i.e., during `nixos-rebuild switch --flake .`). These are additive (`extra-*` keys). This is the preferred method for flake-level binary cache configuration, distinct from `nix.settings` in the NixOS system configuration (which controls the deployed system's runtime Nix).

### Source 5 — Cachix Documentation: Getting Started
URL: `https://docs.cachix.org/getting-started`

The standard NixOS configuration pattern for Cachix caches uses `nix.settings.substituters` and `nix.settings.trusted-public-keys` within the NixOS system configuration. For public caches no auth token is required. When added to the deployed system's `nix.settings`, the cache is used by all subsequent `nix` invocations on that machine.

### Source 6 — NixOS Wiki: Linux Kernel (`boot.kernelPackages` + VirtualBox GuestAdditions)
URL: `https://wiki.nixos.org/wiki/Linux_kernel`

VirtualBox GuestAdditions are built as an out-of-tree kernel module using `config.boot.kernelPackages.callPackage`. Any custom kernel that provides valid kernel headers and `moduleBuildDependencies` should be buildable. However, custom kernels that deviate significantly from mainline (e.g., out-of-tree patches in non-standard locations, Rust components, broadcom blobs) can cause `GuestAdditions` build failures. The bazzite kernel applies multiple patches and includes out-of-tree drivers (`evdi`, `broadcom-wl`). VirtualBox compatibility must be verified empirically.

### Source 7 — `vex-kernels` `pkgs/linux-bazzite.nix` (direct code inspection)
URL: `https://github.com/VictoryTek/vex-kernels/blob/main/pkgs/linux-bazzite.nix`

The bazzite kernel is built using `linuxManualConfig` with the Fedora/Bazzite kernel config (Rust disabled for nixpkgs compatibility). It applies four patch series: `patch-1-redhat`, `patch-2-handheld`, `patch-3-akmods` (includes `evdi`, `broadcom-wl`, and other out-of-tree drivers), `patch-4-amdgpu-vrr-whitelist`. The `patch-3-akmods` adds custom drivers under `drivers/custom/`. This means VirtualBox GuestAdditions (`vboxguest`, `vboxsf`, `vboxvideo`) must be compiled against this patched source tree — a non-trivial risk.

### Source 8 — NixOS Module System: Priority Merge Rules
URL: `https://nix.dev/tutorials/module-system/module-system` (inferred from nixpkgs source and NixOS wiki)

`lib.mkOverride n`: lower `n` = higher precedence. `lib.mkForce` = `lib.mkOverride 50`, `lib.mkDefault` = `lib.mkOverride 1000`. When two definitions at the same priority conflict for a non-list option, NixOS throws a conflict error. To override a `lib.mkForce`, the consuming module must use `lib.mkForce` itself.

---

## 4. Proposed Solution Architecture

### 4.1 Decision: `nixpkgs.follows` for `kernel-bazzite`

**Decision: Do NOT add `inputs.nixpkgs.follows = "nixpkgs"` for the `kernel-bazzite` input.**

Rationale:
- The upstream `vex-kernels` flake deliberately pins `nixos-unstable`, consistent with the Bazzite project targeting latest kernel infrastructure.
- This mirrors the established project precedent for `nix-cachyos-kernel`, which also omits `nixpkgs.follows` with explicit documentation.
- The `nixosModules.default` uses the host's `pkgs` (nixos-25.11) for all build operations, so the flake's own nixpkgs pin does not affect the NixOS system build. The only consequence of not adding `follows` is a second `nixpkgs` lock entry (nixos-unstable) in `flake.lock`.
- Adding `follows` could theoretically break standalone `nix build .#linux-bazzite` usage against the vex-kernels flake if `nixos-25.11` lacks required build tooling.

### 4.2 Decision: Kernel Priority Override

**Decision: Use `lib.mkForce` directly in `hosts/vm.nix` to elect the Bazzite kernel.**

The bazzite `nixosModules.default` is not imported because it only sets `lib.mkDefault`, which is defeated by both existing lower-priority-number settings. Instead, `hosts/vm.nix` directly calls the bazzite kernel derivation with `lib.mkForce`, consistent with how `modules/gpu/vm.nix` forces the LTS kernel today (same mechanism, different value).

`modules/gpu/vm.nix` is **not modified**. Its `lib.mkForce pkgs.linuxPackages` is superseded by a second `lib.mkForce` in `hosts/vm.nix`. When two `lib.mkForce` (same priority 50) definitions exist for the same option, the one defined in the later-evaluated module wins. `hosts/vm.nix` is listed after `modules/gpu/vm.nix` in its imports list, so its setting takes precedence.

> **NixOS merge behavior for same-priority conflicting definitions:** For scalar options at equal priority, NixOS uses the last definition encountered in import order (left-to-right, depth-first). Since `hosts/vm.nix`'s own body is evaluated after all its `imports`, a `lib.mkForce` in the body wins over the same-priority `lib.mkForce` in an imported module.

### 4.3 Decision: Cachix Cache Placement

Two changes are required:

1. **`flake.nix` `nixConfig`** — adds the Cachix cache for **build-time** substitution (during `nixos-rebuild switch/dry-build --flake .#vexos-vm`).
2. **`hosts/vm.nix` `nix.settings`** — adds the Cachix cache to the **deployed VM system's runtime** Nix configuration (for ongoing use on the VM host).

The cache is NOT added to `configuration.nix` (which propagates to all four host outputs). It is scoped to `hosts/vm.nix` for the system-level setting.

### 4.4 Decision: VirtualBox GuestAdditions Risk

VirtualBox GuestAdditions compatibility with the bazzite kernel is **untested** and considered a risk. The spec does NOT pre-emptively disable VirtualBox. The implementation proceeds with VirtualBox enabled; if `nixos-rebuild dry-build` fails due to `vboxguest`/`vboxsf` compilation, a fallback option is available (see §6.3).

---

## 5. Implementation Steps

### Step 1 — Add the `kernel-bazzite` input to `flake.nix`

**File:** `flake.nix`

**Location:** After the `nix-cachyos-kernel` input block (approximately line 44).

**Change — add input:**
```nix
    # Bazzite kernel — gaming and handheld optimized kernel for VM testing.
    # CRITICAL: Do NOT add inputs.nixpkgs.follows = "nixpkgs" here.
    # vex-kernels pins nixos-unstable internally; the nixosModule evaluates
    # pkgs from the host system, but the flake may require unstable tooling
    # for standalone builds. Mirrors the established precedent for
    # nix-cachyos-kernel. A separate nixpkgs lock entry is acceptable.
    kernel-bazzite = {
      url = "github:VictoryTek/vex-kernels";
    };
```

**Change — update `outputs` function signature** (add `kernel-bazzite` to the destructured inputs):
```nix
  outputs = { self, nixpkgs, nixpkgs-unstable, nix-gaming, nix-cachyos-kernel, home-manager, kernel-bazzite, ... }@inputs:
```

**Change — add Cachix to `nixConfig`** (at the top of `flake.nix`):
```nix
  nixConfig = {
    extra-substituters = [
      "https://attic.xuyh0120.win/lantian"
      "https://cache.garnix.io"
      "https://vex-kernels.cachix.org"
    ];
    extra-trusted-public-keys = [
      "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc="
      "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
      "vex-kernels.cachix.org-1:V2rsF5p1U/J45nH+4uIJ45OlkWmqtv098pZSyq5ABck="
    ];
  };
```

**No change to `commonModules`.** The bazzite kernel is intentionally NOT added to `commonModules` — it must remain scoped to `vexos-vm` only.

---

### Step 2 — Update `hosts/vm.nix` to apply the Bazzite kernel

**File:** `hosts/vm.nix`

**Complete replacement:**
```nix
# hosts/vm.nix
# vexos — Virtual machine guest build (QEMU/KVM + VirtualBox).
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-vm
#
# Bazzite kernel: applied here for testing purposes only.
# lib.mkForce is required to override both:
#   - modules/performance.nix (normal priority, CachyOS kernel)
#   - modules/gpu/vm.nix (lib.mkForce, LTS kernel)
# Since both existing settings use equal or lower priority-number, the last
# lib.mkForce in evaluation order (this file's body) wins.
#
# Cachix binary cache (vex-kernels.cachix.org) is configured here for the
# deployed VM system's runtime Nix. The build-time cache is in flake.nix nixConfig.
#
# Bootloader: NOT configured here — set it in your host's hardware-configuration.nix.
#
# BIOS VM example (add to /etc/nixos/hardware-configuration.nix):
#   boot.loader.systemd-boot.enable = false;
#   boot.loader.grub = { enable = true; device = "/dev/sda"; efiSupport = false; };
#
# UEFI VM example (add to /etc/nixos/hardware-configuration.nix):
#   boot.loader.systemd-boot.enable = false;
#   boot.loader.grub = { enable = true; device = "nodev"; efiSupport = true;
#                        efiInstallAsRemovable = true; };
{ pkgs, lib, inputs, ... }:
{
  imports = [
    ../configuration.nix
    ../modules/gpu/vm.nix
  ];

  # Bazzite kernel — overrides modules/gpu/vm.nix LTS (lib.mkForce) and
  # modules/performance.nix CachyOS setting (normal priority).
  # Uses lib.mkForce so this file's body takes highest precedence.
  boot.kernelPackages = lib.mkForce (
    pkgs.linuxPackagesFor (pkgs.callPackage "${inputs.kernel-bazzite}/pkgs/linux-bazzite.nix" {})
  );

  # Cachix binary cache for vex-kernels (bazzite kernel) — deployed system runtime.
  # Build-time cache is handled via nixConfig in flake.nix.
  nix.settings = {
    substituters = [
      "https://vex-kernels.cachix.org"
    ];
    trusted-public-keys = [
      "vex-kernels.cachix.org-1:V2rsF5p1U/J45nH+4uIJ45OlkWmqtv098pZSyq5ABck="
    ];
  };

  # Distinguish the VM host on the network
  networking.hostName = "vexos-vm";
}
```

**Notes on this implementation:**
- `pkgs` and `lib` are available as NixOS module arguments because `specialArgs = { inherit inputs; }` is already declared in `flake.nix`'s `nixosConfigurations.vexos-vm`. `inputs` is therefore accessible.
- `"${inputs.kernel-bazzite}"` evaluates to the flake source store path; appending `/pkgs/linux-bazzite.nix` gives the absolute path to the kernel derivation within the locked source tree.
- `nix.settings.substituters` in a module **appends** to — it does not replace — the substituters defined in `configuration.nix`, because `nix.settings.substituters` is a list option that merges across modules.
- `modules/gpu/vm.nix` is **not modified**. Its `lib.mkForce pkgs.linuxPackages` is present but superseded by the `lib.mkForce` defined here (evaluated later in import order depth-first traversal, with the host file's own body evaluated after its imports).

---

### Step 3 — Lock file update

After editing `flake.nix`, run:
```bash
nix flake update kernel-bazzite
```
This adds only the `kernel-bazzite` entry to `flake.lock` without updating other inputs.

---

### Step 4 — Preflight validation

Run the existing preflight script:
```bash
bash scripts/preflight.sh
```
Or run the dry-build manually to validate:
```bash
sudo nixos-rebuild dry-build --flake .#vexos-vm
```
The dry-build will:
1. Download (or use cache for) the bazzite kernel source and build the kernel.
2. Attempt to build VirtualBox GuestAdditions (`vboxguest`, `vboxsf`) against the bazzite kernel.
3. Verify all other VM module settings compile correctly.

Also confirm that AMD/NVIDIA/Intel outputs are unaffected:
```bash
sudo nixos-rebuild dry-build --flake .#vexos-amd
sudo nixos-rebuild dry-build --flake .#vexos-nvidia
sudo nixos-rebuild dry-build --flake .#vexos-intel
```

---

## 6. Risks and Mitigations

### 6.1 Risk: VirtualBox GuestAdditions Build Failure (HIGH)

**Description:** `modules/gpu/vm.nix` enables `virtualisation.virtualbox.guest.enable = true`, which builds `vboxguest`, `vboxsf`, and `vboxvideo` out-of-tree kernel modules. The bazzite kernel applies extensive out-of-tree patches (from `patch-3-akmods`) and includes custom drivers under `drivers/custom/`. This non-standard source tree may break VirtualBox GuestAdditions compilation.

**Indicators:** `nixos-rebuild dry-build` fails with errors during the `vboxguest` or `vboxsf` derivation build.

**Mitigation:** If VirtualBox GuestAdditions fail, add the following to `hosts/vm.nix` to disable VirtualBox and rely on QEMU/SPICE only:
```nix
# Disable VirtualBox GuestAdditions — incompatible with bazzite kernel patches.
# QEMU guest agent (services.qemuGuest.enable) and SPICE (services.spice-vdagentd.enable)
# remain active for clipboard sync and auto-resize in QEMU/KVM sessions.
virtualisation.virtualbox.guest.enable = lib.mkForce false;
```
QEMU/KVM with SPICE remains fully functional without VirtualBox GuestAdditions.

### 6.2 Risk: `lib.mkForce` Conflict Behavior

**Description:** Both `modules/gpu/vm.nix` and `hosts/vm.nix` set `boot.kernelPackages` via `lib.mkForce` (priority 50). NixOS resolves ties at the same priority by depth-first evaluation order: the module whose definition is encountered last wins.

**Expected behavior:** Since `modules/gpu/vm.nix` is listed in `hosts/vm.nix`'s `imports`, and `imports` are evaluated before the host module body, the `lib.mkForce` in the `hosts/vm.nix` body is encountered last and wins.

**Verification:** Confirm the correct kernel is active after switching: `uname -r` should show `6.17.7-ba28` (or the current bazzite version from `pins.json`).

**Mitigation if wrong kernel selected:** Wrap `hosts/vm.nix`'s `boot.kernelPackages` with `lib.mkOverride 49` instead of `lib.mkForce` to explicitly outrank `modules/gpu/vm.nix`'s `lib.mkForce` (50):
```nix
boot.kernelPackages = lib.mkOverride 49 (
  pkgs.linuxPackagesFor (pkgs.callPackage "${inputs.kernel-bazzite}/pkgs/linux-bazzite.nix" {})
);
```

### 6.3 Risk: Binary Cache Miss (Build Time)

**Description:** If the Cachix binary cache (`vex-kernels.cachix.org`) is unavailable or does not contain a pre-built binary for the pinned kernel version, NixOS will attempt to compile the kernel locally. Kernel compilation requires significant time (30–90 minutes on typical hardware) and memory (>4 GB recommended).

**Indicators:** `nix build` shows `building linux-bazzite-6.17.x-ba28` locally.

**Mitigation:** The `nixConfig` addition to `flake.nix` ensures the cache is tried first. If a miss occurs, allow sufficient time and resources for local compilation. The Cachix cache is populated by the `vex-kernels` GitHub Actions CI for every kernel update.

### 6.4 Risk: `nix flake check` Evaluates All Outputs

**Description:** `nix flake check` evaluates all `nixosConfigurations` outputs, including `vexos-vm`. If the bazzite kernel cannot be evaluated (e.g., `pins.json` format mismatch, network-fetched source unavailable in pure-eval mode), the flake check fails.

**Mitigation:** Run `nix flake check --impure` (already used in the preflight script) since the flake requires impure evaluation due to `hardware-configuration.nix` at `/etc/nixos/`.

### 6.5 Risk: `nix.settings.substituters` Merge Semantics

**Description:** `nix.settings.substituters` in `hosts/vm.nix` declares only `https://vex-kernels.cachix.org`. NixOS merges list options across modules, so this appends to `configuration.nix`'s existing substituters list (which includes `cache.nixos.org`, `nix-gaming.cachix.org`, and the CachyOS caches). The result is the union of all declared substituters.

**No action needed** — this is the correct behavior. Documented here for clarity.

### 6.6 Risk: Kernel Module Namespace Conflicts (`virtio_gpu`, `qxl`, `broadcom-wl`)

**Description:** The bazzite kernel includes `broadcom-wl` and `evdi` via `patch-3-akmods`. If the VM system attempts to auto-load these modules, there may be udev noise or minor errors. The `boot.kernelModules = [ "qxl" ]` and `boot.initrd.kernelModules = [ "virtio_gpu" ]` settings should still function correctly.

**Mitigation:** No action required for typical QEMU/KVM usage. The extra modules are loadable but not loaded unless requested.

### 6.7 Risk: Flake Inputs Drift (`vex-kernels` is a fast-moving repo)

**Description:** `github:VictoryTek/vex-kernels` does not pin to a tag or branch; it tracks `main`. The `flake.lock` will pin a specific commit. Running `nix flake update kernel-bazzite` will advance the kernel version.

**Mitigation:** Manual `nix flake update kernel-bazzite` is required to get new kernel versions. The lock file provides reproducibility; drift only occurs on explicit update.

---

## 7. Dependencies

| Dependency | Source | Version / Ref | `nixpkgs.follows` |
|-----------|--------|--------------|-------------------|
| `kernel-bazzite` (vex-kernels) | `github:VictoryTek/vex-kernels` | HEAD of `main` (commit-pinned via `flake.lock`) | **OMITTED** (intentional; upstream targets nixos-unstable; consistent with `nix-cachyos-kernel` precedent) |

**Cachix binary cache:**
- Substituter URL: `https://vex-kernels.cachix.org`
- Trusted public key: `vex-kernels.cachix.org-1:V2rsF5p1U/J45nH+4uIJ45OlkWmqtv098pZSyq5ABck=`
- Populated by: `vex-kernels` GitHub Actions CI (`github.com/VictoryTek/vex-kernels/.github/workflows/`)

---

## 8. Configuration Changes Summary

| File | Change Type | Description |
|------|-------------|-------------|
| `flake.nix` | Modify | Add `kernel-bazzite` input (no `nixpkgs.follows`) |
| `flake.nix` | Modify | Add `kernel-bazzite` to `outputs` destructured args |
| `flake.nix` | Modify | Add Cachix cache to `nixConfig.extra-substituters` + `extra-trusted-public-keys` |
| `hosts/vm.nix` | Modify | Expand function args to `{ pkgs, lib, inputs, ... }` |
| `hosts/vm.nix` | Modify | Add `boot.kernelPackages = lib.mkForce (bazzite derivation)` |
| `hosts/vm.nix` | Modify | Add `nix.settings.substituters` + `trusted-public-keys` for Cachix |
| `modules/gpu/vm.nix` | **No change** | Existing `lib.mkForce pkgs.linuxPackages` is superseded in evaluation order |
| `configuration.nix` | **No change** | Bazzite cache scoped to VM only; not added to global `nix.settings` |
| `flake.lock` | New entry | `kernel-bazzite` lock entry added via `nix flake update kernel-bazzite` |

---

## 9. Verification Checklist

Post-implementation, verify:

- [ ] `nix flake check --impure` passes
- [ ] `sudo nixos-rebuild dry-build --flake .#vexos-vm` passes (or documents VBox failure per §6.1)
- [ ] `sudo nixos-rebuild dry-build --flake .#vexos-amd` passes (unaffected)
- [ ] `sudo nixos-rebuild dry-build --flake .#vexos-nvidia` passes (unaffected)
- [ ] `sudo nixos-rebuild dry-build --flake .#vexos-intel` passes (unaffected)
- [ ] After live switch: `uname -r` on VM shows bazzite kernel version (`6.17.x-ba28`-style suffix)
- [ ] `hardware-configuration.nix` is NOT tracked in git
- [ ] `system.stateVersion` in `configuration.nix` is unchanged

---

## 10. Spec File Path

`/home/nimda/Projects/vexos-nix/.github/docs/subagent_docs/bazzite_kernel_vm_spec.md`
