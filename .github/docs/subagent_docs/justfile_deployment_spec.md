# Specification: Justfile Deployment across NixOS Variants

## Current State Analysis
- **`just` Package**: Currently installed as a user package in `home.nix` and as a system package specifically in `hosts/amd.nix`. It is missing from `hosts/vm.nix`, `hosts/nvidia.nix`, and `hosts/intel.nix` (system-wide), although `home.nix` provides it to the user `nimda`.
- **`justfile`**: Exists at the repository root but is not deployed to any location on the target systems.
- **Configuration Structure**:
    - `flake.nix` manages the overall build and imports `home-manager`.
    - `configuration.nix` is the base system config.
    - `home.nix` manages user-level packages and dotfiles for `nimda`.
    - `modules/packages.nix` manages global system packages.

## Problem Definition
The `just` command is inconsistent across variants (system-wide), and the `justfile` is not available on the systems, making it impossible to run `just` commands relative to the project root unless the repo is manually cloned to the exact same path.

## Proposed Solution Architecture

### 1. Global Package Availability
Move `pkgs.just` from `hosts/amd.nix` and `home.nix` to `modules/packages.nix`. This ensures that the `just` binary is available system-wide across all variants (AMD, NVIDIA, Intel, VM) for all users, including root.

### 2. Justfile Deployment
Since the `justfile` is specific to the user's project and home environment, it should be managed via **Home Manager** (`home.nix`).

**Implementation Detail**: Use `home.file.".justfile".source = ./justfile;` (or similar).
However, `just` looks for a `justfile` or `Justfile` in the current directory. To make the project's `justfile` available globally or in a known location:
- Deploy it to the home directory: `home.file.".justfile".source = ./justfile;`
- The user can then run `just` from `~` or symlink it. Or, more cleanly, since the `justfile` is meant for this specific repo, it is often better to keep it in the repo. But the requirement is to "be available", implying a deployment. 
- A better approach for a "system" justfile is to place it in the home directory as a hidden file or a specific config path, but `just` primarily targets the CWD.
- To satisfy the requirement of "deployed to the system" while keeping it in sync, we will link the repo's `justfile` to the user's home directory.

## Implementation Steps

### Step 1: System-wide Package Installation
- **File**: `/home/nimda/Projects/vexos-nix/modules/packages.nix`
- **Action**: Add `pkgs.just` to `environment.systemPackages`.

### Step 2: Remove Redundant Package Declarations
- **File**: `/home/nimda/Projects/vexos-nix/hosts/amd.nix`
- **Action**: Remove `pkgs.just` from `environment.systemPackages`.
- **File**: `/home/nimda/Projects/vexos-nix/home.nix`
- **Action**: Remove `pkgs.just` from `home.packages`.

### Step 3: Deploy Justfile via Home Manager
- **File**: `/home/nimda/Projects/vexos-nix/home.nix`
- **Action**: Add `home.file.".justfile".source = ./justfile;`. (Naming it `.justfile` ensures it doesn't clutter the home root but is accessible).

## Verification Steps

1. **Build Validation**:
    - Run `nix flake check` to ensure no syntax errors.
    - Run `sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm` (and other variants) to verify the closure builds.

2. **Functional Validation (Post-Apply)**:
    - Execute `which just` on all variants to confirm it is located in `/run/current-system/sw/bin/just`.
    - Execute `ls -a ~` to confirm `.justfile` exists in the home directory.
    - Run `just --version` to confirm the binary is functional.

## Risks and Mitigations
- **Path Conflict**: If the user already has a `justfile` in `~`, Home Manager will throw an error.
- **Mitigation**: Use `home.file.".justfile".force = true;` if overrides are desired, or rely on the `backupFileExtension = "backup"` already configured in `flake.nix`.
