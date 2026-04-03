# Specification: Fix Up GTK4 App Missing from VM Variant (Template Path)

**Feature name:** `up_vm_integration`
**Date:** 2026-04-03
**Status:** Ready for implementation

---

## 1. Current State Analysis

### Two code paths for the VM variant

#### Path A — Direct repo build (`nixosConfigurations.vexos-vm`)

```
nixosConfigurations.vexos-vm = nixpkgs.lib.nixosSystem {
  inherit system;
  modules = commonModules ++ [ ./hosts/vm.nix ];
  specialArgs = { inherit inputs; };
};
```

`hosts/vm.nix` is a module function `{ inputs, ... }:` that receives `inputs` via `specialArgs`. It explicitly adds Up to packages:

```nix
environment.systemPackages = [
  inputs.up.packages.x86_64-linux.default
];
```

**Result:** Up IS installed when the developer builds directly from the repo.

#### Path B — End-user template install (`template/etc-nixos-flake.nix`)

The template at `/etc/nixos/flake.nix` only declares two inputs:

```nix
inputs = {
  vexos-nix.url = "github:VictoryTek/vexos-nix";
  nixpkgs.follows = "vexos-nix/nixpkgs";
};
```

It builds the VM variant via:

```nix
vexos-vm = mkVariant "vexos-vm" vexos-nix.nixosModules.gpuVm;
```

Where `mkVariant` assembles these modules:
1. A variant-tracking module (`environment.etc."nixos/vexos-variant"`)
2. `bootloaderModule`
3. `./hardware-configuration.nix`
4. `vexos-nix.nixosModules.base`
5. `vexos-nix.nixosModules.gpuVm`  ← **only the bare GPU driver module**

`hosts/vm.nix` is **never imported** in this path.

### What `nixosModules.gpuVm` currently contains

```nix
gpuVm = ./modules/gpu/vm.nix;
```

`modules/gpu/vm.nix` is a pure GPU/driver module `{ config, lib, pkgs, ... }:` that configures:
- `boot.kernelPackages = lib.mkForce pkgs.linuxPackages_6_6`
- `services.qemuGuest.enable = true`
- `services.spice-vdagentd.enable = true`
- `virtualisation.virtualbox.guest.enable = true`
- `boot.initrd.kernelModules = [ "virtio_gpu" ]`
- `boot.kernelModules = [ "qxl" ]`
- `powerManagement.cpuFreqGovernor = lib.mkForce "performance"`

It contains **no reference to the Up flake input**, nor should it.

---

## 2. Problem Definition

`nixosModules.gpuVm` is a bare path (`./modules/gpu/vm.nix`), not a module function. It therefore has no mechanism to access `inputs.up` from the flake's outer scope.

When the end-user template evaluates `vexos-nix.nixosModules.gpuVm`, it receives only the bare GPU driver configuration. Up is never added to `environment.systemPackages`.

The `up` flake input is already correctly declared in `flake.nix` inputs:

```nix
up = {
  url = "github:VictoryTek/Up";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

And `inputs` is accessible in the outputs function via `@inputs`. The gap is solely that `nixosModules.gpuVm` does not capture `inputs.up` and expose Up as a package.

---

## 3. Proposed Solution

Change `nixosModules.gpuVm` in `flake.nix` from a bare path to an inline module function that:

1. Imports `./modules/gpu/vm.nix` (preserving all existing GPU driver config)
2. Adds `inputs.up.packages.x86_64-linux.default` to `environment.systemPackages`
3. Captures `inputs` from the outer `@inputs` scope — the same pattern already used by `nixosModules.base` to capture `nix-gaming` and `home-manager`

This is a **closed-form fix**: the flake already has `inputs.up` in scope in the `outputs` function; it just needs to be forwarded through the module boundary.

---

## 4. Exact Code Change

### File to change: `flake.nix`

**Before:**

```nix
nixosModules = {
  # Full stack: desktop + gaming + audio + performance + controllers + network + flatpak
  base = { ... }: {
    imports = [
      nix-gaming.nixosModules.pipewireLowLatency
      home-manager.nixosModules.home-manager
      ./configuration.nix
    ];
    home-manager = {
      useGlobalPkgs   = true;
      useUserPackages = true;
      users.nimda     = import ./home.nix;
    };
    nixpkgs.overlays = [
      (final: prev: {
        unstable = import nixpkgs-unstable {
          inherit (final) config;
          inherit (final.stdenv.hostPlatform) system;
        };
      })
    ];
  };

  gpuAmd    = ./modules/gpu/amd.nix;
  gpuNvidia = ./modules/gpu/nvidia.nix;
  gpuVm     = ./modules/gpu/vm.nix;
  gpuIntel  = ./modules/gpu/intel.nix;
  asus      = ./modules/asus.nix;
};
```

**After:**

```nix
nixosModules = {
  # Full stack: desktop + gaming + audio + performance + controllers + network + flatpak
  base = { ... }: {
    imports = [
      nix-gaming.nixosModules.pipewireLowLatency
      home-manager.nixosModules.home-manager
      ./configuration.nix
    ];
    home-manager = {
      useGlobalPkgs   = true;
      useUserPackages = true;
      users.nimda     = import ./home.nix;
    };
    nixpkgs.overlays = [
      (final: prev: {
        unstable = import nixpkgs-unstable {
          inherit (final) config;
          inherit (final.stdenv.hostPlatform) system;
        };
      })
    ];
  };

  gpuAmd    = ./modules/gpu/amd.nix;
  gpuNvidia = ./modules/gpu/nvidia.nix;
  gpuVm     = { ... }: {
    imports = [ ./modules/gpu/vm.nix ];
    # Up: GTK4 + libadwaita system update GUI — VM variant only.
    # inputs.up is captured from the outer @inputs scope (same pattern as
    # nix-gaming / home-manager in nixosModules.base above).
    environment.systemPackages = [ inputs.up.packages.x86_64-linux.default ];
  };
  gpuIntel  = ./modules/gpu/intel.nix;
  asus      = ./modules/asus.nix;
};
```

### Single diff summary

| Location | Old value | New value |
|---|---|---|
| `flake.nix` → `nixosModules.gpuVm` | `./modules/gpu/vm.nix` | Inline module function: imports `./modules/gpu/vm.nix` + adds `inputs.up.packages.x86_64-linux.default` to `environment.systemPackages` |

---

## 5. Why No Other Files Need to Change

| File | Reason unchanged |
|---|---|
| `hosts/vm.nix` | Already correctly installs Up for direct repo builds via `inputs.up.packages.x86_64-linux.default`. No change needed. |
| `modules/gpu/vm.nix` | Pure GPU driver module. It must NOT reference external flake inputs — this preserves modularity and reusability. |
| `template/etc-nixos-flake.nix` | Already consumes `vexos-nix.nixosModules.gpuVm`. Once `gpuVm` is fixed in `flake.nix`, the template path automatically gains Up without any template edits. |
| `flake.nix` inputs section | `up` is already correctly declared with `inputs.nixpkgs.follows = "nixpkgs"`. No change needed. |
| `flake.nix` nixosConfigurations | All four variants already pass `specialArgs = { inherit inputs; }`. The direct-build `vexos-vm` path continues to use `hosts/vm.nix` unchanged. |

---

## 6. Implementation Steps

1. In `flake.nix`, replace the `gpuVm = ./modules/gpu/vm.nix;` line with the inline module function shown in Section 4.
2. No other files require edits.

---

## 7. Verification

After the change, run:

```bash
nix flake check
sudo nixos-rebuild dry-build --flake .#vexos-vm
sudo nixos-rebuild dry-build --flake .#vexos-amd
sudo nixos-rebuild dry-build --flake .#vexos-nvidia
sudo nixos-rebuild dry-build --flake .#vexos-intel
```

All four dry-builds must succeed. The AMD, NVIDIA, and Intel variants are unaffected by the change (their `gpuAmd`, `gpuNvidia`, `gpuIntel` entries remain bare paths).

To confirm Up appears in the VM closure:

```bash
nix build .#nixosConfigurations.vexos-vm.config.system.build.toplevel --dry-run 2>&1 | grep -i "Up\|up-"
```

---

## 8. Risks and Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| `inputs.up.packages.x86_64-linux.default` attribute path changes in a future Up release | Low | The Up flake uses `flake-utils.lib.eachDefaultSystem` which guarantees `packages.${system}.default` as the standard output path. If it changes, `nix flake check` will fail loudly at evaluation time, not silently at runtime. |
| AMD/NVIDIA/Intel variants accidentally broken | None | `gpuAmd`, `gpuNvidia`, and `gpuIntel` remain untouched bare paths. The change is isolated to `gpuVm`. |
| Double-installation of Up in direct repo build (`vexos-vm`) | Negligible | `hosts/vm.nix` adds Up via `environment.systemPackages`; the new `gpuVm` module also adds it. NixOS deduplicates `environment.systemPackages` by store path — the package appears once in the closure. |
| `system.stateVersion` accidentally changed | None | This change touches only the `nixosModules.gpuVm` attribute. It does not touch `configuration.nix` or any host file. |

---

## 9. Summary

The gap is precisely that `nixosModules.gpuVm` is a bare path with no access to `inputs.up`. The fix converts it to an inline module function that captures `inputs.up` from the outer `@inputs` scope and adds it to `environment.systemPackages`. This is a one-line structural change to `flake.nix` consistent with the existing pattern used by `nixosModules.base`.
