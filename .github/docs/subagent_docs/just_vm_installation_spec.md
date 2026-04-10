# Spec: Remove 'just' from VM Role Installation

## Current State Analysis
The `just` package is currently included in `modules/packages.nix` within the `environment.systemPackages` list. This module is imported by `configuration.nix`, which in turn is imported by all host configurations, including `hosts/vm.nix`.

As a result, `just` is installed system-wide on all roles, including the 'desktop vm' variant.

## Problem Definition
The user has reported that `just` is installed on a fresh NixOS installation for the 'desktop vm' role. The goal is to ensure that `just` is not installed for the VM role, as it is likely intended for physical desktop roles where the `justfile` is used for system management and variant switching.

## Proposed Solution
Move the `just` package from the global `modules/packages.nix` to a location where it is only applied to the physical desktop roles (`amd`, `nvidia`, `intel`) and not the `vm` role.

Since `hosts/vm.nix` imports `configuration.nix`, and `configuration.nix` imports `modules/packages.nix`, the most straightforward approach is to remove `just` from `modules/packages.nix` and add it back to the physical host configurations or a shared module that excludes the VM.

However, to maintain a clean structure, we can create a "desktop-common" set of packages or simply add it to the physical host files. Alternatively, we can use a conditional check in `modules/packages.nix`, but the current structure prefers flat modules.

**Decision:** Remove `just` from `modules/packages.nix` and add it to `hosts/amd.nix`, `hosts/nvidia.nix`, and `hosts/intel.nix`.

## Implementation Steps
1. Remove `just` from `environment.systemPackages` in `modules/packages.nix`.
2. Add `pkgs.just` to `environment.systemPackages` in `hosts/amd.nix`.
3. Add `pkgs.just` to `environment.systemPackages` in `hosts/nvidia.nix`.
4. Add `pkgs.just` to `environment.systemPackages` in `hosts/intel.nix`.

## Dependencies
No new dependencies.

## Risks and Mitigations
- **Risk:** Users on the VM role might actually need `just` to run some of the provided recipes.
- **Mitigation:** The VM role's primary purpose is usually testing or lightweight usage. If it's needed, it can be added back specifically to `hosts/vm.nix` if identified as a requirement. For now, we follow the user report that it should not be there by default.
