# Spec: Bazzite Kernel Missing from VM Template

**Feature:** `bazzite_template_fix`
**Date:** 2026-04-01
**Status:** Ready for Implementation

---

## 1. Current State Analysis

`template/etc-nixos-flake.nix` is the template consumers copy to `/etc/nixos/flake.nix` when
setting up a fresh VM host. It references `vexos-nix` as a flake input and builds three
host variants (`vexos-amd`, `vexos-nvidia`, `vexos-vm`) via a shared `mkVariant` helper.

The `mkVariant` function signature is:

```nix
mkVariant = variant: gpuModule: nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  modules =
    let
      modules = if builtins.isList gpuModule then gpuModule else [ gpuModule ];
    in
    [
      { environment.etc."nixos/vexos-variant".text = "${variant}\n"; }
      bootloaderModule
      ./hardware-configuration.nix
      vexos-nix.nixosModules.base
    ] ++ modules;
};
```

The second argument is already normalised: if it is a list it is used directly; if it is a
single module it is wrapped in a list. Passing a list of modules is therefore safe and
already supported.

The VM variant is currently declared as:

```nix
vexos-vm = mkVariant "vexos-vm" vexos-nix.nixosModules.gpuVm;
```

---

## 2. Problem Definition

When a user performs a fresh VM setup using the template and runs:

```bash
sudo nixos-rebuild switch --flake /etc/nixos#vexos-vm
```

the resulting system boots with Linux 6.12.77 (the LTS kernel) rather than the Bazzite
gaming kernel (`linux-bazzite` 6.17.7-ba28). This defeats the purpose of the VM variant,
which is intended to run the same gaming-optimised kernel as the AMD and NVIDIA hosts.

---

## 3. Root Cause

`vexos-nix.nixosModules.gpuVm` (sourced from `modules/gpu/vm.nix`) sets:

```nix
boot.kernelPackages = lib.mkForce pkgs.linuxPackages;  # NixOS priority 50
```

`nixosModules.kernelBazzite` overrides this with:

```nix
boot.kernelPackages = lib.mkOverride 49 (
  pkgs.linuxPackagesFor kernel-bazzite.packages.x86_64-linux.linux-bazzite
);
```

`lib.mkOverride 49` has a *lower* numeric priority value than `lib.mkForce` (priority 50),
which means it wins in NixOS option resolution (lower number = higher precedence).

The template's VM variant passes only `vexos-nix.nixosModules.gpuVm` to `mkVariant`.
`vexos-nix.nixosModules.kernelBazzite` is never included, so the `mkForce` LTS assignment
is never overridden and Linux LTS is installed.

The in-repo host definitions (`hosts/vm.nix`) already include `kernelBazzite` correctly.
The bug exists exclusively in the consumer-facing template.

---

## 4. Proposed Fix

Pass both modules to `mkVariant` as a list for the `vexos-vm` variant:

```nix
vexos-vm = mkVariant "vexos-vm" [
  vexos-nix.nixosModules.gpuVm
  vexos-nix.nixosModules.kernelBazzite
];
```

This mirrors the pattern already used by the in-repo host definitions and is handled
transparently by the existing `builtins.isList` guard in `mkVariant`.

---

## 5. Implementation Steps

1. Open `template/etc-nixos-flake.nix`.
2. Locate the line:
   ```nix
   vexos-vm = mkVariant "vexos-vm" vexos-nix.nixosModules.gpuVm;
   ```
3. Replace it with the multi-module list form (exact change shown in §6).
4. Verify the template evaluates cleanly:
   ```bash
   nix flake check --impure
   ```
5. Optionally confirm kernel version resolves correctly by evaluating the template output
   (if a test environment is available).

No other files require modification for this fix.

---

## 6. Code Change

### File: `template/etc-nixos-flake.nix`

**Before:**

```nix
    vexos-vm = mkVariant "vexos-vm" vexos-nix.nixosModules.gpuVm;
```

**After:**

```nix
    vexos-vm = mkVariant "vexos-vm" [
      vexos-nix.nixosModules.gpuVm
      vexos-nix.nixosModules.kernelBazzite
    ];
```

This is a single-line-to-three-line change. No surrounding code is touched.

---

## 7. Risks and Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| `mkVariant` rejects a list argument | None | `mkVariant` already contains `if builtins.isList gpuModule then gpuModule else [ gpuModule ]`; lists are explicitly supported. |
| `vexos-nix.nixosModules.kernelBazzite` not exported in old flake revisions | Low | The module was introduced in the same commit that added `kernel-bazzite` support; any consumer pinning a revision that includes `gpuVm` will also have `kernelBazzite`. |
| Priority conflict between `gpuVm` and `kernelBazzite` regresses | None | `lib.mkOverride 49` is intentionally designed to beat `lib.mkForce` (50); this is the same mechanism used in the in-repo hosts with no reported issues. |
| Template change breaks AMD/NVIDIA variants | None | Only the `vexos-vm` stanza is modified; `vexos-amd` and `vexos-nvidia` are untouched. |
| Consumers using a custom `mkVariant` without the list guard | Unlikely | Template ships its own `mkVariant` with the guard; consumers who have modified it carry their own risk. |
