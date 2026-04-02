# Spec: Consolidate `vexos-vm` Into a Single NixOS Module

**Feature name:** `vm_kernel_module_fix`
**Date:** 2026-04-02
**Status:** Draft

---

## 1. Problem Statement

The `vexos-vm` variant in `template/etc-nixos-flake.nix` references two separate
`nixosModules` from the upstream `vexos-nix` flake:

```nix
vexos-vm = mkVariant "vexos-vm" [
  vexos-nix.nixosModules.gpuVm
  vexos-nix.nixosModules.kernelBazzite
];
```

`nixosModules.kernelBazzite` was introduced **after** `nixosModules.gpuVm`. Because
the template is downloaded separately from the upstream flake, the following race
condition exists on every fresh install:

1. User runs `sudo curl … -o /etc/nixos/flake.nix …` — gets the **latest** template.
2. User runs `sudo nixos-rebuild switch --flake /etc/nixos#vexos-vm`.
3. Nix auto-generates `/etc/nixos/flake.lock`, pinning `vexos-nix` to whatever
   commit it resolves at that moment.
4. If that commit predates the addition of `kernelBazzite`, the build aborts with:
   ```
   error: attribute 'kernelBazzite' missing
   ```

Every other variant (`vexos-amd`, `vexos-nvidia`, `vexos-intel`) references a
**single** module and is not affected. Only `vexos-vm` is fragile because it
requires two modules that were introduced at different points in history.

---

## 2. Current State Analysis

### `flake.nix` — `nixosModules` section (current)

```nix
nixosModules = {
  base      = { ... }: { imports = [ … ]; … };

  gpuAmd    = ./modules/gpu/amd.nix;
  gpuNvidia = ./modules/gpu/nvidia.nix;
  gpuVm     = ./modules/gpu/vm.nix;          # ← bare path reference
  gpuIntel  = ./modules/gpu/intel.nix;
  asus      = ./modules/asus.nix;

  kernelBazzite = { pkgs, lib, ... }: {
    boot.kernelPackages = lib.mkOverride 49 (
      pkgs.linuxPackagesFor kernel-bazzite.packages.x86_64-linux.linux-bazzite
    );
  };
};
```

`gpuVm` is a **bare path** — it resolves to `modules/gpu/vm.nix` at evaluation
time but carries no Bazzite kernel logic of its own.

### `modules/gpu/vm.nix` (current)

- Enables `qemuGuest`, `spice-vdagentd`, VirtualBox guest additions.
- Sets `boot.initrd.kernelModules = [ "virtio_gpu" ]`.
- Sets `boot.kernelPackages = lib.mkForce pkgs.linuxPackages;` as an LTS baseline
  (priority 50).
- Applies the `makeModulesClosure { allowMissing = true; }` overlay so missing
  kernel modules (e.g. `pcips2`) do not abort the build.

### `template/etc-nixos-flake.nix` (current)

```nix
vexos-vm = mkVariant "vexos-vm" [
  vexos-nix.nixosModules.gpuVm
  vexos-nix.nixosModules.kernelBazzite   # ← second module, added later
];
```

`mkVariant` already normalises a list to a module list via `builtins.isList`, so
the two-element list is valid Nix — but the fragility is the introduction of a
second attribute lookup against a potentially stale flake revision.

### `hosts/vm.nix` (current)

Uses `inputs.kernel-bazzite` via `specialArgs` (the **direct-build path**, not the
module path). This file is unaffected by this change and must remain unchanged.

---

## 3. Root Cause

The two-module design for `vexos-vm` creates a temporal dependency between the
**template** (always latest) and the **flake revision** (pinned at lock time).
Any new `nixosModules` attribute referenced by the template becomes a potential
breakage vector whenever the pinned revision is older than the attribute's
introduction commit.

The correct design is: **every variant maps to exactly one `nixosModule`**. All
logic needed to boot that variant must be self-contained in that single module.

---

## 4. Proposed Solution

### 4.1 Merge `kernelBazzite` into `gpuVm`

Change `nixosModules.gpuVm` from a bare path reference to an **inline NixOS module**
that:

1. Imports `./modules/gpu/vm.nix` (preserving all existing VM guest logic).
2. Applies the Bazzite kernel override directly — capturing `kernel-bazzite` from
   the `outputs` function closure, exactly as `kernelBazzite` does today.

```nix
# AFTER (proposed)
gpuVm = { pkgs, lib, ... }: {
  imports = [ ./modules/gpu/vm.nix ];

  # Bazzite kernel override — lib.mkOverride 49 beats modules/gpu/vm.nix
  # lib.mkForce (priority 50) so the gaming kernel is always selected.
  boot.kernelPackages = lib.mkOverride 49 (
    pkgs.linuxPackagesFor kernel-bazzite.packages.x86_64-linux.linux-bazzite
  );
};
```

### 4.2 Remove `nixosModules.kernelBazzite`

The `kernelBazzite` attribute on `nixosModules` becomes redundant once its logic
lives inside `gpuVm`. Remove the attribute entirely to eliminate the stale-revision
attack surface.

> **Note:** `kernelBazzite` is not referenced anywhere else in the repo (confirmed
> by grep). `hosts/vm.nix` uses `inputs.kernel-bazzite` directly and is unaffected.

### 4.3 Simplify `template/etc-nixos-flake.nix`

Replace the two-element list with a single module reference, consistent with all
other variants:

```nix
# BEFORE
vexos-vm = mkVariant "vexos-vm" [
  vexos-nix.nixosModules.gpuVm
  vexos-nix.nixosModules.kernelBazzite
];

# AFTER
vexos-vm = mkVariant "vexos-vm" vexos-nix.nixosModules.gpuVm;
```

`mkVariant` accepts either a single module or a list (via the `builtins.isList`
guard), so passing a single value is valid and preferred.

### 4.4 Leave `hosts/vm.nix` unchanged

`hosts/vm.nix` sets `boot.kernelPackages` via `inputs.kernel-bazzite` through
`specialArgs`. This is the **direct-build** path used by `nixosConfigurations.vexos-vm`
and is entirely independent of `nixosModules`. No change is needed.

---

## 5. Priority Mechanics (Unchanged)

The Bazzite kernel override priority chain is preserved:

| Source | Option | Priority |
|---|---|---|
| `modules/performance.nix` | `boot.kernelPackages` (CachyOS) | 100 (normal) |
| `modules/gpu/vm.nix` | `boot.kernelPackages` (LTS) | 50 (`lib.mkForce`) |
| `gpuVm` inline module (proposed) | `boot.kernelPackages` (Bazzite) | 49 (`lib.mkOverride 49`) |

Priority 49 < 50, so the Bazzite definition in `gpuVm` wins over both the `mkForce`
LTS baseline from `vm.nix` and the normal-priority CachyOS setting from
`performance.nix`. This matches the behaviour of the current `kernelBazzite`
module exactly.

---

## 6. Files to Modify

| File | Change |
|---|---|
| `flake.nix` | Convert `gpuVm` from path to inline module; remove `kernelBazzite` attribute |
| `template/etc-nixos-flake.nix` | Replace two-element list with single `gpuVm` module reference |

**Files NOT to modify:** `modules/gpu/vm.nix`, `hosts/vm.nix`,
`hosts/amd.nix`, `hosts/nvidia.nix`, `hosts/intel.nix`, `configuration.nix`.

---

## 7. Implementation Steps

1. **Edit `flake.nix`**
   - Locate the `nixosModules` attrset.
   - Replace `gpuVm = ./modules/gpu/vm.nix;` with the inline module defined
     in §4.1.
   - Delete the `kernelBazzite = { pkgs, lib, ... }: { … };` entry.

2. **Edit `template/etc-nixos-flake.nix`**
   - Replace the `vexos-vm` two-element list with a single module reference
     as defined in §4.3.

3. **Validation**
   - Run `nix flake check` — verifies flake structure and evaluates all outputs.
   - Run `sudo nixos-rebuild dry-build --flake .#vexos-vm` — confirms the VM
     closure evaluates correctly with the merged module.
   - Run `sudo nixos-rebuild dry-build --flake .#vexos-amd` and `.#vexos-nvidia`
     to confirm no regressions.
   - Grep for any surviving reference to `kernelBazzite` — should return empty.

---

## 8. Risks and Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| Priority override no longer applies | Low | `lib.mkOverride 49` from the inline module and `lib.mkForce` (priority 50) from `vm.nix` interact identically to the current two-module arrangement. The kernel selection order is unchanged. |
| `kernel-bazzite` not in closure scope | Low | `kernel-bazzite` is already bound in the `outputs` function scope. The inline module closure captures it exactly as `kernelBazzite` did. |
| External consumers of `kernelBazzite` break | Negligible | The attribute is not advertised in docs; repo grep confirms zero downstream references outside the template. |
| `hosts/vm.nix` regression | None | `hosts/vm.nix` uses `inputs.kernel-bazzite` via `specialArgs`, a completely separate path. |

---

## 9. Acceptance Criteria

- [ ] `nix flake check` exits 0.
- [ ] `sudo nixos-rebuild dry-build --flake .#vexos-vm` exits 0.
- [ ] `sudo nixos-rebuild dry-build --flake .#vexos-amd` exits 0.
- [ ] `sudo nixos-rebuild dry-build --flake .#vexos-nvidia` exits 0.
- [ ] `grep -r "kernelBazzite" .` returns no results (outside this spec file).
- [ ] `vexos-vm` in `template/etc-nixos-flake.nix` references a single module, not a list.
- [ ] `nixosModules.gpuVm` in `flake.nix` is an inline module that imports `./modules/gpu/vm.nix`.
