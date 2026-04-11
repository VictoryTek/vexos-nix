# Stateless Rebuild — Implementation Specification

**Feature:** stateless_rebuild  
**Date:** 2026-04-10  
**Status:** Pending Implementation  
**Author:** Specification subagent

---

## Table of Contents

1. [Current State Analysis](#1-current-state-analysis)
2. [Problem Definitions](#2-problem-definitions)
3. [Architecture Decision](#3-architecture-decision)
4. [Implementation Steps — File by File](#4-implementation-steps)
5. [Risk Analysis](#5-risk-analysis)

---

## 1. Current State Analysis

### 1.1 Repository Structure (stateless-relevant files)

```
flake.nix                        # declares disko input + four stateless nixosConfigurations + nixosModules.statelessBase
modules/stateless-disk.nix       # disko-based GPT/LUKS/Btrfs layout; options: enable, device, enableLuks, luksName, memorySize
modules/impermanence.nix         # tmpfs root + declarative persistence; references LUKS in comments
template/stateless-disko.nix     # standalone disko CLI template (not a NixOS module)
scripts/stateless-setup.sh       # ISO-based initial disk setup — runs disko then nixos-install
hosts/stateless-amd.nix          # vexos-stateless-amd host file; sets disk.enable = true, device = mkDefault "/dev/nvme0n1"
hosts/stateless-nvidia.nix       # same pattern as amd
hosts/stateless-intel.nix        # same pattern as amd
hosts/stateless-vm.nix           # sets device = "/dev/vda", enableLuks = false
configuration-stateless.nix      # sets vexos.impermanence.enable = true; refers to stateless-setup.sh
template/etc-nixos-flake.nix     # thin host wrapper; mkStatelessVariant uses nixosModules.statelessBase
```

### 1.2 Current disko Integration Points

**`flake.nix` — inputs section:**
```nix
disko = {
  url = "github:nix-community/disko/latest";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

**`flake.nix` — outputs function signature:**
```nix
outputs = { self, nixpkgs, nixpkgs-unstable, nix-gaming, home-manager, impermanence, disko, up, ... }@inputs:
```

**`flake.nix` — four stateless nixosConfigurations (vexos-stateless-{amd,nvidia,intel,vm}):**
```nix
modules = commonModules ++ [
  ./hosts/stateless-<variant>.nix
  impermanence.nixosModules.impermanence
  inputs.disko.nixosModules.disko      # ← present in all four
];
```

**`flake.nix` — nixosModules.statelessBase (consumed by template/etc-nixos-flake.nix):**
```nix
statelessBase = { lib, ... }: {
  imports = [
    ...
    impermanence.nixosModules.impermanence
    disko.nixosModules.disko             # ← also present here
    ./configuration-stateless.nix
    ./modules/stateless-disk.nix
  ];
  ...
  vexos.stateless.disk = {
    enable     = true;
    device     = lib.mkDefault "/dev/nvme0n1";
    enableLuks = lib.mkDefault true;     # ← must be removed with the option
  };
};
```

**`modules/stateless-disk.nix` — current option set:**
- `vexos.stateless.disk.enable` (bool, default false)
- `vexos.stateless.disk.device` (str, default "/dev/nvme0n1")
- `vexos.stateless.disk.enableLuks` (bool, default true)
- `vexos.stateless.disk.luksName` (str, default "cryptroot")
- `vexos.stateless.disk.memorySize` (str, default "25%") — unused, informational only

**`modules/stateless-disk.nix` — current config block:**
Sets `disko.devices.disk.main` with conditional LUKS/plainBtrfs branches based on `cfg.enableLuks`.

**`template/stateless-disko.nix` — function signature:**
```nix
{ disk ? "/dev/nvme0n1", enableLuks ? true, luksName ? "cryptroot" }:
```

**`scripts/stateless-setup.sh` — LUKS determination logic:**
```bash
if [ "$VARIANT" = "vm" ]; then
  LUKS_BOOL="false"
  echo ""
  echo -e "${CYAN}VM variant selected — disk encryption (LUKS2) will be skipped.${RESET}"
else
  LUKS_BOOL="true"
fi
```
End-of-script LUKS warning:
```bash
echo -e "${YELLOW}${BOLD}IMPORTANT:${RESET} Store your LUKS passphrase in a secure location."
echo "  If you lose it, all data on the encrypted volume is unrecoverable."
```

**`hosts/stateless-vm.nix` — LUKS option usage:**
```nix
vexos.stateless.disk = {
  enable     = true;
  device     = "/dev/vda";
  enableLuks = false;       # ← must be removed with the option
};
```

**`hosts/stateless-{amd,nvidia,intel}.nix`** — do NOT currently set `enableLuks`; they only set `enable` and `device`. No changes needed to those option blocks, though the descriptions referencing LUKS in comments may need updating.

---

## 2. Problem Definitions

### Problem 1 — disko 1.13.0 Compatibility (`diskoFile` argument)

**Symptom:**
```
error: function 'anonymous lambda' called with unexpected argument 'diskoFile'
at /tmp/vexos-*-disk.nix:19:1:
    { disk ? "/dev/nvme0n1", enableLuks ? true, luksName ? "cryptroot" }:
```

**Root cause:** disko 1.13.0 now passes a `diskoFile` argument to the Nix function in the template file when calling the disko CLI. The current `template/stateless-disko.nix` declares only three named parameters and does not accept `diskoFile`, so Nix evaluation fails.

**Fix:** Add `diskoFile ? null` to the function signature. Since the argument is unused internally (disko passes it for its own bookkeeping), accepting and ignoring it is the correct approach.

---

### Problem 2 — Rebuild to Stateless Goes to Black Screen

**Symptom:** Running `nixos-rebuild switch --flake .#vexos-stateless-<variant>` on an existing NixOS system (FAT32 `/boot` + plain Btrfs root, no subvolumes) results in a black screen / boot failure.

**Root cause:**
- The current `modules/stateless-disk.nix` sets `disko.devices`, which causes the disko NixOS module to generate `fileSystems` entries referencing Btrfs subvolumes `@nix` (→ `/nix`) and `@persist` (→ `/persistent`).
- On an existing system where these subvolumes have never been created, the initrd cannot mount `/nix` or `/persistent`.
- Because `/nix` cannot be mounted, the Nix store is inaccessible — the switch fails to boot.

**Fix:** Decouple disko from the NixOS module system for stateless configurations. Replace `disko.devices` with direct `fileSystems` declarations using `lib.mkDefault`, so that `hardware-configuration.nix` (which has UUID-based paths) can override them at higher priority after migration.

---

### Problem 3 — LUKS Must Be Removed From All Stateless Builds

**Symptom / Requirement:** The user requires no LUKS encryption in any stateless build variant. Currently, `enableLuks` defaults to `true` in `modules/stateless-disk.nix` and in `Nixon/osModules.statelessBase`, and the ISO setup script enables it for all non-VM variants.

**Fix:**
- Remove the `enableLuks` and `luksName` NixOS options entirely from `modules/stateless-disk.nix`.
- Remove `enableLuks = lib.mkDefault true` from `nixosModules.statelessBase` in `flake.nix`.
- Remove the LUKS conditional from `scripts/stateless-setup.sh`; set `LUKS_BOOL="false"` unconditionally.
- Remove the LUKS passphrase warning from the end of `scripts/stateless-setup.sh`.
- Update `template/stateless-disko.nix` to default `enableLuks` to `false` (keep the parameter for backward compatibility with direct CLI invocations, but LUKS is no longer the default).

---

### Problem 4 — Make Rebuild the Primary Workflow

**Requirement:** `nixos-rebuild switch` must be the default, primary way to activate stateless mode on an existing system. The ISO-based `stateless-setup.sh` remains valid for fresh installs, but existing systems need a migration path.

**Fix:** Create `scripts/migrate-to-stateless.sh` — an in-place migration script that:
1. Detects the existing Btrfs root and FAT32 boot partitions.
2. Creates Btrfs subvolumes `@nix` and `@persist` on the existing root partition.
3. Copy-on-write copies `/nix` into `@nix` using `--reflink=always`.
4. Regenerates `hardware-configuration.nix` with `--no-filesystems`.
5. Appends UUID-based stateless `fileSystems` declarations to the regenerated `hardware-configuration.nix`.
6. Prompts for GPU variant and hostname, then runs `nixos-rebuild switch`.

---

### Problem 5 — Partition Scheme (Boot Derivation)

**Requirement:** FAT32 `/boot` (EFI) + single Btrfs root partition is the target. When no separate boot device is specified by the user, the boot and root partition devices must be derived automatically from the disk device.

**Fix:** In `modules/stateless-disk.nix`, derive boot and root partition paths using a `let` binding that checks whether the device name matches the nvme/mmcblk naming convention:
- `nvme*` or `mmcblk*`: append `p1` / `p2` (e.g., `/dev/nvme0n1p1`, `/dev/nvme0n1p2`)
- All others (sata, virtio, scsi): append `1` / `2` (e.g., `/dev/sda1`, `/dev/sda2`, `/dev/vda1`)

---

## 3. Architecture Decision

### 3.1 Decoupling disko From the NixOS Module System

**Current architecture (broken for rebuild):**

```
flake.nix:
  inputs.disko.nixosModules.disko  →  imported by all 4 stateless nixosConfigurations
                                   →  imported by nixosModules.statelessBase

modules/stateless-disk.nix:
  config.disko.devices = { ... }   →  disko NixOS module generates fileSystems from this
                                   →  fileSystems reference @nix and @persist subvolumes
                                   →  subvolumes do not exist on an existing system → boot failure
```

**New architecture:**

```
flake.nix:
  disko input REMOVED entirely
  inputs.disko.nixosModules.disko REMOVED from all stateless nixosConfigurations
  disko.nixosModules.disko REMOVED from nixosModules.statelessBase

modules/stateless-disk.nix:
  config.fileSystems."/boot"        = lib.mkDefault { ... }
  config.fileSystems."/nix"         = lib.mkDefault { ... neededForBoot = true; }
  config.fileSystems."/persistent"  = lib.mkDefault { ... neededForBoot = true; }
  ← no disko.devices at all

template/stateless-disko.nix:
  Unchanged except: add `diskoFile ? null` to function signature, change enableLuks default to false
  ← used only by the disko CLI during initial disk formatting
  ← NOT imported as a NixOS module anywhere
```

### 3.2 How `lib.mkDefault` Resolves the Rebuild Conflict

Nix module system priority scale (lower number = higher priority):
- `lib.mkForce` = priority 50 (highest)
- Default declarations = priority 100
- `lib.mkDefault` = priority 1000 (lowest)

The conflict resolution works as follows:

| Scenario | `hardware-configuration.nix` | `stateless-disk.nix` | Winner |
|---|---|---|---|
| **Fresh install** (`--no-filesystems`) | No fileSystems entries | `lib.mkDefault` fileSystems | stateless-disk.nix wins (only entry) |
| **After migration** | UUID-based fileSystems at priority 100 | `lib.mkDefault` at priority 1000 | hardware-configuration.nix wins for `device`/`options` |
| **Conflict on same attribute** | UUID-based device string | `lib.mkDefault` device string | hardware-configuration.nix wins automatically — no merge error |

This means `nixos-rebuild switch` works correctly on both paths:
- **Fresh install**: disko formats the disk, nixos-install uses `--no-filesystems` hw-config, mkDefault entries populate fileSystems.
- **Migrated system**: migration script writes UUID-based entries to hw-config, those take priority over mkDefault — correct UUIDs are used at boot.

### 3.3 Why disko Is Still Used for Initial Setup

`template/stateless-disko.nix` is retained as a standalone disko CLI template. The ISO setup script (`stateless-setup.sh`) continues to use it via `nix run github:nix-community/disko/latest`. This is correct and separate from the NixOS module concern — disko's CLI is a partition formatting tool, not a NixOS module dependency.

---

## 4. Implementation Steps

### File 1: `flake.nix`

**Location:** `/home/nimda/Projects/vexos-nix/flake.nix`

#### Change 1.1 — Remove `disko` from `inputs`

Remove the following block from the `inputs` attribute set:

```nix
# REMOVE THIS ENTIRE BLOCK:
# nix-community/disko: declarative disk partitioning for the stateless role.
# Used by modules/stateless-disk.nix to generate fileSystems and LUKS config.
disko = {
  url = "github:nix-community/disko/latest";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

#### Change 1.2 — Remove `disko` from the outputs function signature

**Before:**
```nix
outputs = { self, nixpkgs, nixpkgs-unstable, nix-gaming, home-manager, impermanence, disko, up, ... }@inputs:
```

**After:**
```nix
outputs = { self, nixpkgs, nixpkgs-unstable, nix-gaming, home-manager, impermanence, up, ... }@inputs:
```

#### Change 1.3 — Remove `inputs.disko.nixosModules.disko` from all four stateless nixosConfigurations

Apply to each of the four blocks: `vexos-stateless-amd`, `vexos-stateless-nvidia`, `vexos-stateless-intel`, `vexos-stateless-vm`.

**Before (example: vexos-stateless-amd):**
```nix
nixosConfigurations.vexos-stateless-amd = nixpkgs.lib.nixosSystem {
  inherit system;
  modules = commonModules ++ [
    ./hosts/stateless-amd.nix
    impermanence.nixosModules.impermanence
    inputs.disko.nixosModules.disko
  ];
  specialArgs = { inherit inputs; };
};
```

**After:**
```nix
nixosConfigurations.vexos-stateless-amd = nixpkgs.lib.nixosSystem {
  inherit system;
  modules = commonModules ++ [
    ./hosts/stateless-amd.nix
    impermanence.nixosModules.impermanence
  ];
  specialArgs = { inherit inputs; };
};
```

Repeat identically for `vexos-stateless-nvidia`, `vexos-stateless-intel`, and `vexos-stateless-vm`.

#### Change 1.4 — Remove `disko.nixosModules.disko` and `enableLuks` from `nixosModules.statelessBase`

**Before:**
```nix
statelessBase = { lib, ... }: {
  imports = [
    nix-gaming.nixosModules.pipewireLowLatency
    home-manager.nixosModules.home-manager
    impermanence.nixosModules.impermanence
    disko.nixosModules.disko
    ./configuration-stateless.nix
    ./modules/stateless-disk.nix
  ];
  ...
  vexos.stateless.disk = {
    enable     = true;
    device     = lib.mkDefault "/dev/nvme0n1";
    enableLuks = lib.mkDefault true;
  };
};
```

**After:**
```nix
statelessBase = { lib, ... }: {
  imports = [
    nix-gaming.nixosModules.pipewireLowLatency
    home-manager.nixosModules.home-manager
    impermanence.nixosModules.impermanence
    ./configuration-stateless.nix
    ./modules/stateless-disk.nix
  ];
  ...
  vexos.stateless.disk = {
    enable = true;
    device = lib.mkDefault "/dev/nvme0n1";
  };
};
```

Also remove `statelessGpuVm`'s `enableLuks` reference:

**Before:**
```nix
statelessGpuVm = { lib, ... }: {
  imports = [ ./modules/gpu/vm.nix ];
  vexos.stateless.disk.device    = lib.mkForce "/dev/vda";
  vexos.stateless.disk.enableLuks = lib.mkForce false;
};
```

**After:**
```nix
statelessGpuVm = { lib, ... }: {
  imports = [ ./modules/gpu/vm.nix ];
  vexos.stateless.disk.device = lib.mkForce "/dev/vda";
};
```

---

### File 2: `modules/stateless-disk.nix`

**Location:** `/home/nimda/Projects/vexos-nix/modules/stateless-disk.nix`

Complete rewrite of this file. The module header, options block (for `enable` and `device`), and the config block are all replaced. LUKS-related options are removed entirely.

**New complete file content:**

```nix
# modules/stateless-disk.nix
# Declarative filesystem layout for the VexOS stateless role.
#
# Disk layout is declared by modules/stateless-disk.nix (plain Btrfs, no LUKS).
# For new installs use scripts/stateless-setup.sh (formats disk via disko CLI).
# For existing systems use scripts/migrate-to-stateless.sh (in-place migration).
#
# This module declares fileSystems entries using lib.mkDefault so that
# hardware-configuration.nix (generated by nixos-generate-config) can override
# the device paths with UUID-based entries at higher priority.
#
# Priority model:
#   lib.mkDefault (priority 1000) — this module's fallback declarations
#   Default priority  (priority 100) — hardware-configuration.nix entries WIN
#
# Fresh install: nixos-install uses --no-filesystems hw-config, so no
#   fileSystems are declared there → mkDefault entries are used directly.
# Migrated system: migration script writes UUID-based fileSystems to hw-config
#   → those entries take priority → mkDefault entries are effectively ignored
#   for device/options, preventing UUID/path conflicts at boot.
{ config, lib, ... }:

let
  cfg = config.vexos.stateless.disk;
in
{
  options.vexos.stateless.disk = {

    enable = lib.mkOption {
      type        = lib.types.bool;
      default     = false;
      description = ''
        Enable the stateless filesystem layout for this host.
        When true, declares fileSystems entries for /boot, /nix, and
        /persistent using lib.mkDefault, allowing hardware-configuration.nix
        to override with UUID-based paths after running
        scripts/migrate-to-stateless.sh.
        Requires a block device to be specified via vexos.stateless.disk.device.
      '';
    };

    device = lib.mkOption {
      type        = lib.types.str;
      default     = "/dev/nvme0n1";
      description = ''
        The FULL DISK block device for this host.
        Used to derive partition paths:
          nvme* / mmcblk*  → p1 (EFI) and p2 (Btrfs root)
          All others       → 1  (EFI) and 2  (Btrfs root)
        Examples: "/dev/nvme0n1"  "/dev/sda"  "/dev/vda"
        Override per host: vexos.stateless.disk.device = "/dev/sda";
        Note: hardware-configuration.nix UUID entries take priority over the
        device-path-derived values declared here.
      '';
    };

  };

  config = lib.mkIf cfg.enable (
    let
      # Detect NVMe / eMMC naming: these use p1/p2 partition suffixes.
      # SATA, virtio, and SCSI drives use numeric suffixes directly (1/2).
      isNvmeStyle = builtins.match ".*(nvme|mmcblk).*" cfg.device != null;
      bootPart    = if isNvmeStyle then "${cfg.device}p1" else "${cfg.device}1";
      rootPart    = if isNvmeStyle then "${cfg.device}p2" else "${cfg.device}2";
    in
    {
      # EFI System Partition — FAT32
      # lib.mkDefault allows hardware-configuration.nix (UUID-based) to win.
      fileSystems."/boot" = lib.mkDefault {
        device  = bootPart;
        fsType  = "vfat";
        options = [ "fmask=0077" "dmask=0077" ];
      };

      # Btrfs @nix subvolume — Nix store (persistent across reboots)
      # neededForBoot = true: required so the initrd can mount /nix before
      # switching root, making the Nix store available to stage-2 init.
      fileSystems."/nix" = lib.mkDefault {
        device        = rootPart;
        fsType        = "btrfs";
        options       = [ "subvol=@nix" "compress=zstd" "noatime" ];
        neededForBoot = true;
      };

      # Btrfs @persist subvolume — persistent state across reboots
      # neededForBoot = true: required so impermanence bind mounts are
      # available during early userspace (before systemd activates services).
      fileSystems."/persistent" = lib.mkDefault {
        device        = rootPart;
        fsType        = "btrfs";
        options       = [ "subvol=@persist" "compress=zstd" "noatime" ];
        neededForBoot = true;
      };
    }
  );
}
```

**Options removed vs. current:**
| Option | Current | New | Reason |
|---|---|---|---|
| `enable` | ✓ kept | ✓ kept | Required |
| `device` | ✓ kept | ✓ kept | Required |
| `enableLuks` | bool, default true | **REMOVED** | No LUKS in stateless builds |
| `luksName` | str, default "cryptroot" | **REMOVED** | No LUKS in stateless builds |
| `memorySize` | str, default "25%" | **REMOVED** | Unused informational option |

---

### File 3: `template/stateless-disko.nix`

**Location:** `/home/nimda/Projects/vexos-nix/template/stateless-disko.nix`

#### Change 3.1 — Add `diskoFile ? null` to the function signature

**Before:**
```nix
{ disk ? "/dev/nvme0n1", enableLuks ? true, luksName ? "cryptroot" }:
```

**After:**
```nix
{ disk ? "/dev/nvme0n1", enableLuks ? false, luksName ? "cryptroot", diskoFile ? null }:
```

Two changes in one line:
1. `enableLuks ? true` → `enableLuks ? false` (LUKS no longer the default)
2. Add `, diskoFile ? null` (accepts and ignores the argument passed by disko 1.13.0+)

#### Change 3.2 — Update file header comments

**Before:**
```nix
# template/stateless-disko.nix
# Standalone disko disk layout for the VexOS stateless role.
# Used by scripts/stateless-setup.sh during initial installation from the NixOS ISO.
#
# This is NOT a NixOS module — it is a plain Nix file passed directly to the
# disko CLI.  The NixOS module equivalent is modules/stateless-disk.nix.
#
# Usage:
#   sudo nix run 'github:nix-community/disko/latest' -- \
#     --mode destroy,format,mount \
#     /tmp/vexos-stateless-disk.nix \
#     --arg disk '"/dev/nvme0n1"' \
#     --arg enableLuks 'true'
#
# Parameters:
#   disk       — block device path (string, e.g. "/dev/nvme0n1")
#   enableLuks — whether to use LUKS2 encryption (bool, default true)
#   luksName   — name of the LUKS device-mapper entry (string, default "cryptroot")
```

**After:**
```nix
# template/stateless-disko.nix
# Standalone disko disk layout for the VexOS stateless role.
# Used by scripts/stateless-setup.sh during initial installation from the NixOS ISO.
#
# This is NOT a NixOS module — it is a plain Nix file passed directly to the
# disko CLI.  It is decoupled from the NixOS module system; the NixOS-side
# filesystem declarations live in modules/stateless-disk.nix.
#
# Disko 1.13+ compatibility: the `diskoFile` argument is accepted and ignored;
# disko passes it automatically when invoking the template function.
#
# Rebuild-first workflow: for existing systems, use scripts/migrate-to-stateless.sh
# instead of this template.  This template is only needed for fresh disk setup.
#
# Usage (fresh install from NixOS ISO):
#   sudo nix run 'github:nix-community/disko/latest' -- \
#     --mode destroy,format,mount \
#     /tmp/vexos-stateless-disk.nix \
#     --arg disk '"/dev/nvme0n1"'
#
# Parameters:
#   disk       — block device path (string, e.g. "/dev/nvme0n1")
#   enableLuks — whether to use LUKS2 encryption (bool, default false — LUKS disabled)
#   luksName   — name of the LUKS device-mapper entry (string, default "cryptroot")
#   diskoFile  — accepted and ignored (passed automatically by disko 1.13+)
```

---

### File 4: `hosts/stateless-amd.nix`

**Location:** `/home/nimda/Projects/vexos-nix/hosts/stateless-amd.nix`

**Current state:** Does NOT currently set `enableLuks`. The option block is:
```nix
vexos.stateless.disk = {
  enable = true;
  device = lib.mkDefault "/dev/nvme0n1";
};
```

**Required change:** None to the option block itself (no `enableLuks` present). However, the module-level comment referencing LUKS should be updated if present.

Verify the file contains no reference to `enableLuks` before declaring no change needed. Current content confirmed — no `enableLuks` in this file.

**Net change: No modification required to the Nix option block.**

---

### File 5: `hosts/stateless-nvidia.nix`

**Location:** `/home/nimda/Projects/vexos-nix/hosts/stateless-nvidia.nix`

**Current state:** Same as amd — no `enableLuks` in the option block.

**Net change: No modification required to the Nix option block.**

---

### File 6: `hosts/stateless-intel.nix`

**Location:** `/home/nimda/Projects/vexos-nix/hosts/stateless-intel.nix`

**Current state:** Same as amd — no `enableLuks` in the option block.

**Net change: No modification required to the Nix option block.**

---

### File 7: `hosts/stateless-vm.nix`

**Location:** `/home/nimda/Projects/vexos-nix/hosts/stateless-vm.nix`

#### Change 7.1 — Remove `enableLuks = false`

**Before:**
```nix
vexos.stateless.disk = {
  enable     = true;
  device     = "/dev/vda";
  enableLuks = false;
};
```

**After:**
```nix
vexos.stateless.disk = {
  enable = true;
  device = "/dev/vda";
};
```

The `enableLuks` option no longer exists on the module — setting it would cause an "unknown option" evaluation error.

---

### File 8: `scripts/stateless-setup.sh`

**Location:** `/home/nimda/Projects/vexos-nix/scripts/stateless-setup.sh`

#### Change 8.1 — Replace LUKS conditional with unconditional `LUKS_BOOL="false"`

**Before:**
```bash
# ---------- Determine LUKS setting ------------------------------------------
if [ "$VARIANT" = "vm" ]; then
  LUKS_BOOL="false"
  echo ""
  echo -e "${CYAN}VM variant selected — disk encryption (LUKS2) will be skipped.${RESET}"
else
  LUKS_BOOL="true"
fi
```

**After:**
```bash
# ---------- LUKS is disabled for all stateless builds -----------------------
# All variants use plain Btrfs (no LUKS). Encryption at rest is out of scope
# for the stateless role; use full-disk encryption at the hypervisor or
# hardware level if required.
LUKS_BOOL="false"
```

#### Change 8.2 — Update the installation summary to show `LUKS: disabled (no encryption)`

**Before:**
```bash
echo -e "${BOLD}Installation summary:${RESET}"
echo "  Disk:       ${DISK}"
echo "  GPU variant: ${VARIANT}"
echo "  Hostname:   ${HOSTNAME}"
echo "  LUKS:       ${LUKS_BOOL}"
echo "  Flake target: vexos-stateless-${VARIANT}"
```

**After:**
```bash
echo -e "${BOLD}Installation summary:${RESET}"
echo "  Disk:        ${DISK}"
echo "  GPU variant: ${VARIANT}"
echo "  Hostname:    ${HOSTNAME}"
echo "  LUKS:        disabled (no encryption)"
echo "  Flake target: vexos-stateless-${VARIANT}"
```

#### Change 8.3 — Update the hostname prompt default from `vexos-stateless` to `vexos`

**Before:**
```bash
# ---------- Prompt: hostname -------------------------------------------------
echo ""
printf "Enter hostname [vexos-stateless]: "
read -r HOSTNAME_INPUT
HOSTNAME="${HOSTNAME_INPUT:-vexos-stateless}"
```

**After:**
```bash
# ---------- Prompt: hostname -------------------------------------------------
echo ""
printf "Enter hostname [vexos]: "
read -r HOSTNAME_INPUT
HOSTNAME="${HOSTNAME_INPUT:-vexos}"
```

#### Change 8.4 — Remove the LUKS passphrase warning at the end of the script

**Before (at end of script, before the reboot prompt):**
```bash
echo -e "${GREEN}${BOLD}============================================================${RESET}"
echo -e "${GREEN}${BOLD}  ✓ VexOS Stateless installation complete!${RESET}"
echo -e "${GREEN}${BOLD}============================================================${RESET}"
echo ""
echo -e "${BOLD}Next steps:${RESET}"
echo "  1. Set a root password if needed:  nixos-enter --root /mnt -- passwd"
echo "  2. Remove the live ISO from your boot device."
echo "  3. Reboot: sudo reboot"
echo ""
echo -e "${YELLOW}${BOLD}IMPORTANT:${RESET} Store your LUKS passphrase in a secure location."
echo "  If you lose it, all data on the encrypted volume is unrecoverable."
echo ""
```

**After:**
```bash
echo -e "${GREEN}${BOLD}============================================================${RESET}"
echo -e "${GREEN}${BOLD}  ✓ VexOS Stateless installation complete!${RESET}"
echo -e "${GREEN}${BOLD}============================================================${RESET}"
echo ""
echo -e "${BOLD}Next steps:${RESET}"
echo "  1. Set a root password if needed:  nixos-enter --root /mnt -- passwd"
echo "  2. Remove the live ISO from your boot device."
echo "  3. Reboot: sudo reboot"
echo ""
```

---

### File 9: `scripts/migrate-to-stateless.sh` (NEW FILE)

**Location:** `/home/nimda/Projects/vexos-nix/scripts/migrate-to-stateless.sh`

This is the most important new file. It performs an in-place migration of an existing NixOS system (FAT32 `/boot` + plain Btrfs root with no subvolumes) to the stateless layout required by `vexos-stateless-<variant>`.

**Complete file content:**

```bash
#!/usr/bin/env bash
# =============================================================================
# migrate-to-stateless.sh — VexOS Stateless Migration — In-Place Conversion
# Repository: https://github.com/VictoryTek/vexos-nix
#
# What this script does:
#   1. Verifies the existing disk layout (Btrfs root + FAT32 /boot)
#   2. Creates Btrfs subvolumes @nix and @persist on the existing root partition
#   3. Copy-on-write copies /nix into @nix (instant reflink on same Btrfs fs)
#   4. Backs up and regenerates hardware-configuration.nix (--no-filesystems)
#   5. Appends UUID-based stateless fileSystems declarations to hw-config
#   6. Runs nixos-rebuild switch to the chosen vexos-stateless-<variant>
#
# Prerequisites:
#   - NixOS already installed with FAT32 /boot and a plain Btrfs root partition
#   - btrfs-progs available (btrfs command)
#   - Running as root or with sudo
#   - NOT running from a NixOS live ISO
#
# IMPORTANT: Run this on the installed system, NOT from the NixOS live ISO.
#   For a fresh install on an unformatted disk, use scripts/stateless-setup.sh.
# =============================================================================

set -euo pipefail

MOUNT_TMPDIR="/mnt/vexos-migrate-btrfs"

# ---------- Color helpers ----------------------------------------------------
if [ -t 1 ] && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  CYAN='\033[0;36m'
  BOLD='\033[1m'
  RESET='\033[0m'
else
  RED='' GREEN='' YELLOW='' CYAN='' BOLD='' RESET=''
fi

# ---------- Header -----------------------------------------------------------
echo ""
echo -e "${BOLD}${CYAN}============================================================${RESET}"
echo -e "${BOLD}${CYAN}   VexOS Stateless Migration — In-Place Conversion${RESET}"
echo -e "${BOLD}${CYAN}============================================================${RESET}"
echo ""
echo -e "${YELLOW}  This script converts an existing NixOS system to the stateless${RESET}"
echo -e "${YELLOW}  layout by creating Btrfs subvolumes and updating hw-config.${RESET}"
echo -e "${YELLOW}  Run this on the installed system, NOT from the NixOS live ISO.${RESET}"
echo ""

# ---------- Safety: must be root ---------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${RED}Error: This script must be run as root (or via sudo).${RESET}"
  exit 1
fi

# ---------- Safety: must NOT be running from a NixOS live ISO ---------------
# Live ISOs set systemd unit labels; check for the most reliable marker.
if grep -q "copytoram\|cow_space\|NIXOS_ISO" /proc/cmdline 2>/dev/null; then
  echo -e "${RED}Error: This script appears to be running from a NixOS live ISO.${RESET}"
  echo -e "${RED}Use scripts/stateless-setup.sh for fresh installs from the ISO.${RESET}"
  exit 1
fi
# Additional check: live ISOs typically mount / as tmpfs or overlay
ROOT_FS_TYPE="$(findmnt -n -o FSTYPE /)"
if [ "$ROOT_FS_TYPE" = "tmpfs" ] || [ "$ROOT_FS_TYPE" = "overlay" ]; then
  echo -e "${RED}Error: Root filesystem is ${ROOT_FS_TYPE}. This looks like a live environment.${RESET}"
  echo -e "${RED}Use scripts/stateless-setup.sh for fresh installs from the ISO.${RESET}"
  exit 1
fi

# ---------- Check tool availability ------------------------------------------
if ! command -v btrfs &>/dev/null; then
  echo -e "${RED}Error: 'btrfs' command not found. Install btrfs-progs and retry.${RESET}"
  echo "  nix-shell -p btrfs-progs"
  exit 1
fi
if ! command -v blkid &>/dev/null; then
  echo -e "${RED}Error: 'blkid' command not found (should be available on all NixOS installs).${RESET}"
  exit 1
fi
if ! command -v findmnt &>/dev/null; then
  echo -e "${RED}Error: 'findmnt' command not found (util-linux, should be available on all NixOS installs).${RESET}"
  exit 1
fi

# ---------- Detect existing disk layout ---------------------------------------
echo -e "${BOLD}Detecting existing disk layout...${RESET}"

# Find the block device currently mounted as /
ROOT_DEVICE="$(findmnt -n -o SOURCE /)"
if [ -z "$ROOT_DEVICE" ]; then
  echo -e "${RED}Error: Cannot determine the root (/) device from findmnt.${RESET}"
  exit 1
fi
# Resolve device-mapper or bind-mount indirection (take the real block device)
ROOT_DEVICE="$(realpath "$ROOT_DEVICE")"

# Verify root is Btrfs
ROOT_FSTYPE="$(findmnt -n -o FSTYPE /)"
if [ "$ROOT_FSTYPE" != "btrfs" ]; then
  echo -e "${RED}Error: Root filesystem is '${ROOT_FSTYPE}', not btrfs.${RESET}"
  echo -e "${RED}The stateless layout requires a Btrfs root partition.${RESET}"
  exit 1
fi

# Find /boot device (must be vfat)
BOOT_DEVICE="$(findmnt -n -o SOURCE /boot)"
if [ -z "$BOOT_DEVICE" ]; then
  echo -e "${RED}Error: Cannot determine the /boot device from findmnt.${RESET}"
  echo -e "${RED}Ensure /boot is separately mounted (FAT32 EFI partition).${RESET}"
  exit 1
fi
BOOT_DEVICE="$(realpath "$BOOT_DEVICE")"
BOOT_FSTYPE="$(findmnt -n -o FSTYPE /boot)"
if [ "$BOOT_FSTYPE" != "vfat" ]; then
  echo -e "${RED}Error: /boot filesystem is '${BOOT_FSTYPE}', not vfat.${RESET}"
  echo -e "${RED}The stateless layout requires a FAT32 EFI /boot partition.${RESET}"
  exit 1
fi

# Get UUIDs via blkid
ROOT_UUID="$(blkid -s UUID -o value "$ROOT_DEVICE")"
BOOT_UUID="$(blkid -s UUID -o value "$BOOT_DEVICE")"
if [ -z "$ROOT_UUID" ] || [ -z "$BOOT_UUID" ]; then
  echo -e "${RED}Error: Could not determine UUIDs for root or boot partition.${RESET}"
  echo "  ROOT_DEVICE=${ROOT_DEVICE}  ROOT_UUID=${ROOT_UUID}"
  echo "  BOOT_DEVICE=${BOOT_DEVICE}  BOOT_UUID=${BOOT_UUID}"
  exit 1
fi

echo "  Root partition:  ${ROOT_DEVICE}  (UUID: ${ROOT_UUID})"
echo "  Boot partition:  ${BOOT_DEVICE}  (UUID: ${BOOT_UUID})"
echo ""

# ---------- Check for existing subvolumes ------------------------------------
echo -e "${BOLD}Checking for existing Btrfs subvolumes on ${ROOT_DEVICE}...${RESET}"
mkdir -p "$MOUNT_TMPDIR"

# Mount raw Btrfs (no subvol) to inspect subvolume list
mount -t btrfs -o subvolid=5 "$ROOT_DEVICE" "$MOUNT_TMPDIR"
EXISTING_SUBVOLS="$(btrfs subvolume list "$MOUNT_TMPDIR" 2>/dev/null | awk '{print $NF}')"
umount "$MOUNT_TMPDIR"

SUBVOL_CONFLICT=false
if echo "$EXISTING_SUBVOLS" | grep -q "@nix"; then
  echo -e "${YELLOW}  Warning: Btrfs subvolume @nix already exists on ${ROOT_DEVICE}.${RESET}"
  SUBVOL_CONFLICT=true
fi
if echo "$EXISTING_SUBVOLS" | grep -q "@persist"; then
  echo -e "${YELLOW}  Warning: Btrfs subvolume @persist already exists on ${ROOT_DEVICE}.${RESET}"
  SUBVOL_CONFLICT=true
fi

if [ "$SUBVOL_CONFLICT" = "true" ]; then
  echo ""
  echo -e "${YELLOW}One or more target subvolumes already exist. This may indicate the migration${RESET}"
  echo -e "${YELLOW}was previously run (partially or fully).${RESET}"
  echo ""
  printf "Proceed anyway? Existing subvolumes will be PRESERVED. [yes/N] "
  read -r PROCEED_CONFLICT
  if [ "${PROCEED_CONFLICT}" != "yes" ]; then
    echo "Aborting."
    exit 0
  fi
fi

# ---------- GPU variant prompt -----------------------------------------------
echo ""
echo -e "${BOLD}Select your GPU variant:${RESET}"
echo "  1) AMD    — AMD GPU (RADV, ROCm, LACT)"
echo "  2) NVIDIA — NVIDIA GPU (proprietary, open kernel modules)"
echo "  3) Intel  — Intel iGPU or Arc dGPU"
echo "  4) VM     — QEMU/KVM or VirtualBox guest"
echo ""

VARIANT=""
while [ -z "$VARIANT" ]; do
  printf "Enter choice [1-4] or name (amd / nvidia / intel / vm): "
  read -r INPUT
  case "${INPUT,,}" in
    1|amd)    VARIANT="amd"    ;;
    2|nvidia) VARIANT="nvidia" ;;
    3|intel)  VARIANT="intel"  ;;
    4|vm)     VARIANT="vm"     ;;
    *)
      echo -e "${RED}Invalid selection '${INPUT}'. Please enter 1, 2, 3, 4, amd, nvidia, intel, or vm.${RESET}"
      ;;
  esac
done

# ---------- Hostname prompt --------------------------------------------------
echo ""
printf "Enter hostname [vexos]: "
read -r HOSTNAME_INPUT
HOSTNAME="${HOSTNAME_INPUT:-vexos}"

# ---------- Summary and final confirmation -----------------------------------
echo ""
echo -e "${BOLD}Migration summary:${RESET}"
echo "  Root partition:  ${ROOT_DEVICE}  (UUID: ${ROOT_UUID})"
echo "  Boot partition:  ${BOOT_DEVICE}  (UUID: ${BOOT_UUID})"
echo "  GPU variant:     ${VARIANT}"
echo "  Hostname:        ${HOSTNAME}"
echo "  Flake target:    vexos-stateless-${VARIANT}"
echo ""
echo -e "${YELLOW}This will:${RESET}"
echo "  1. Create Btrfs subvolumes @nix and @persist on ${ROOT_DEVICE}"
echo "  2. Copy /nix → @nix using Btrfs reflink (CoW, instant on same fs)"
echo "  3. Back up and regenerate /etc/nixos/hardware-configuration.nix"
echo "  4. Append stateless fileSystems declarations to hardware-configuration.nix"
echo "  5. Run: sudo nixos-rebuild switch --flake /etc/nixos#vexos-stateless-${VARIANT}"
echo ""
printf "Proceed? [yes/N] "
read -r PROCEED
if [ "${PROCEED}" != "yes" ]; then
  echo "Aborting."
  exit 0
fi

# ---------- Mount raw Btrfs filesystem ---------------------------------------
echo ""
echo -e "${BOLD}Mounting raw Btrfs filesystem at ${MOUNT_TMPDIR}...${RESET}"
mkdir -p "$MOUNT_TMPDIR"
mount -t btrfs -o subvolid=5 "$ROOT_DEVICE" "$MOUNT_TMPDIR"

# ---------- Create subvolumes ------------------------------------------------
echo ""
echo -e "${BOLD}Creating Btrfs subvolumes...${RESET}"

if btrfs subvolume list "$MOUNT_TMPDIR" | awk '{print $NF}' | grep -q "^@nix$"; then
  echo -e "${YELLOW}  @nix already exists — skipping creation.${RESET}"
else
  btrfs subvolume create "$MOUNT_TMPDIR/@nix"
  echo -e "${GREEN}  ✓ Created @nix${RESET}"
fi

if btrfs subvolume list "$MOUNT_TMPDIR" | awk '{print $NF}' | grep -q "^@persist$"; then
  echo -e "${YELLOW}  @persist already exists — skipping creation.${RESET}"
else
  btrfs subvolume create "$MOUNT_TMPDIR/@persist"
  echo -e "${GREEN}  ✓ Created @persist${RESET}"
fi

# ---------- Copy /nix to @nix using Btrfs reflink ----------------------------
# --reflink=always: copy-on-write within the same Btrfs filesystem.
# This is near-instant because no data is physically duplicated; extents are
# shared until either copy is modified. Only metadata is written immediately.
echo ""
echo -e "${BOLD}Copying /nix → @nix using Btrfs reflink (copy-on-write)...${RESET}"
echo -e "${YELLOW}  This may take a moment for the metadata copy. No data is physically duplicated.${RESET}"
cp -a --reflink=always /nix/. "$MOUNT_TMPDIR/@nix/"
echo -e "${GREEN}  ✓ /nix copied to @nix${RESET}"

# ---------- Unmount raw Btrfs ------------------------------------------------
echo ""
echo -e "${BOLD}Unmounting ${MOUNT_TMPDIR}...${RESET}"
umount "$MOUNT_TMPDIR"
rmdir "$MOUNT_TMPDIR" 2>/dev/null || true
echo -e "${GREEN}  ✓ Unmounted${RESET}"

# ---------- Back up hardware-configuration.nix --------------------------------
HW_CONFIG="/etc/nixos/hardware-configuration.nix"
HW_CONFIG_BACKUP="${HW_CONFIG}.pre-stateless"

echo ""
echo -e "${BOLD}Backing up hardware-configuration.nix...${RESET}"
if [ -f "$HW_CONFIG" ]; then
  cp "$HW_CONFIG" "$HW_CONFIG_BACKUP"
  echo -e "${GREEN}  ✓ Backed up to ${HW_CONFIG_BACKUP}${RESET}"
else
  echo -e "${YELLOW}  Warning: ${HW_CONFIG} not found — skipping backup.${RESET}"
fi

# ---------- Regenerate hardware-configuration.nix ----------------------------
echo ""
echo -e "${BOLD}Regenerating hardware-configuration.nix (--no-filesystems)...${RESET}"
nixos-generate-config --no-filesystems
echo -e "${GREEN}  ✓ ${HW_CONFIG} regenerated${RESET}"

# ---------- Append stateless fileSystems declarations ------------------------
echo ""
echo -e "${BOLD}Appending stateless fileSystems declarations to hardware-configuration.nix...${RESET}"

# Safety check: confirm file exists and ends with a closing brace
if [ ! -f "$HW_CONFIG" ]; then
  echo -e "${RED}Error: ${HW_CONFIG} not found after nixos-generate-config.${RESET}"
  exit 1
fi

# Insert the fileSystems block before the final closing '}'
# We use a temp file to avoid in-place sed issues with multiline content.
TMPFILE="$(mktemp)"
# Strip the last closing '}' line, append fileSystems declarations, then re-add '}'
head -n -1 "$HW_CONFIG" > "$TMPFILE"
cat >> "$TMPFILE" << EOF

  # Stateless filesystem layout — written by scripts/migrate-to-stateless.sh
  # These entries take priority over modules/stateless-disk.nix (mkDefault)
  # because hardware-configuration.nix is evaluated at default priority (100).
  # Do NOT remove these entries; they are required for the stateless boot.
  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/${BOOT_UUID}";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
  };
  fileSystems."/nix" = {
    device = "/dev/disk/by-uuid/${ROOT_UUID}";
    fsType = "btrfs";
    options = [ "subvol=@nix" "compress=zstd" "noatime" ];
    neededForBoot = true;
  };
  fileSystems."/persistent" = {
    device = "/dev/disk/by-uuid/${ROOT_UUID}";
    fsType = "btrfs";
    options = [ "subvol=@persist" "compress=zstd" "noatime" ];
    neededForBoot = true;
  };
}
EOF
mv "$TMPFILE" "$HW_CONFIG"
echo -e "${GREEN}  ✓ fileSystems declarations appended${RESET}"

# ---------- Run nixos-rebuild switch -----------------------------------------
FLAKE_TARGET="vexos-stateless-${VARIANT}"
echo ""
echo -e "${BOLD}Running nixos-rebuild switch targeting ${CYAN}${FLAKE_TARGET}${RESET}${BOLD}...${RESET}"
echo -e "${YELLOW}This may take a while — it will download and build the NixOS closure.${RESET}"
echo ""
nixos-rebuild switch --flake "/etc/nixos#${FLAKE_TARGET}"

# ---------- Completion -------------------------------------------------------
echo ""
echo -e "${GREEN}${BOLD}============================================================${RESET}"
echo -e "${GREEN}${BOLD}  ✓ VexOS Stateless migration complete!${RESET}"
echo -e "${GREEN}${BOLD}============================================================${RESET}"
echo ""
echo -e "${BOLD}Next steps:${RESET}"
echo "  1. Reboot to activate the stateless configuration."
echo "  2. After reboot, / will be a fresh tmpfs — only /nix and /persistent survive."
echo "  3. Your old Nix store data remains on the root partition outside @nix"
echo "     and can be removed after confirming the new layout works correctly:"
echo "     (Mount raw Btrfs and remove files not under any subvolume)"
echo ""
echo -e "${YELLOW}Backup preserved at: ${HW_CONFIG_BACKUP}${RESET}"
echo ""
printf "Reboot now? [y/N] "
read -r REBOOT_CHOICE
case "${REBOOT_CHOICE,,}" in
  y|yes)
    echo "Rebooting..."
    reboot
    ;;
  *)
    echo ""
    echo -e "${YELLOW}Skipping reboot. Run 'sudo reboot' when ready.${RESET}"
    echo ""
    ;;
esac
```

**File permissions:** The file must be made executable after creation:
```bash
chmod +x scripts/migrate-to-stateless.sh
```

---

### File 10: `modules/impermanence.nix`

**Location:** `/home/nimda/Projects/vexos-nix/modules/impermanence.nix`

#### Change 10.1 — Update module header comment

**Before:**
```nix
# modules/impermanence.nix
# Filesystem impermanence for the VexOS stateless role.
#
# This module implements a tmpfs-rooted NixOS system where everything
# outside of /nix and /persistent is wiped on every reboot, providing
# Tails-like ephemeral behaviour (similar to Tails Linux / Deep Freeze).
#
# Disk layout (LUKS2 + Btrfs subvolumes) is handled declaratively by
# modules/stateless-disk.nix using disko. No manual hardware-configuration.nix
# edits are required. See .github/docs/subagent_docs/stateless_disk_spec.md.
#
# Run scripts/stateless-setup.sh on the NixOS ISO to format the disk before
# deploying any stateless host configuration.  The script sets up the required
# LUKS-encrypted Btrfs layout and calls nixos-install automatically.
```

**After:**
```nix
# modules/impermanence.nix
# Filesystem impermanence for the VexOS stateless role.
#
# This module implements a tmpfs-rooted NixOS system where everything
# outside of /nix and /persistent is wiped on every reboot, providing
# Tails-like ephemeral behaviour (similar to Tails Linux / Deep Freeze).
#
# Disk layout is declared by modules/stateless-disk.nix (plain Btrfs, no LUKS).
# For new installs use scripts/stateless-setup.sh (formats disk from NixOS ISO).
# For existing systems use scripts/migrate-to-stateless.sh (in-place migration).
```

#### Change 10.2 — Update the assertion message

**Before:**
```nix
message = ''
  vexos.impermanence.enable = true requires
  fileSystems."${cfg.persistentPath}" to be declared with neededForBoot = true.
  This is normally satisfied automatically by modules/stateless-disk.nix.
  Check that stateless-disk.nix is imported in your stateless host file.
'';
```

**After:**
```nix
message = ''
  vexos.impermanence.enable = true requires
  fileSystems."${cfg.persistentPath}" to be declared with neededForBoot = true.
  This is normally satisfied by modules/stateless-disk.nix or by running
  scripts/migrate-to-stateless.sh (which writes UUID-based fileSystems entries
  directly into /etc/nixos/hardware-configuration.nix).
  Check that stateless-disk.nix is imported in your stateless host file.
'';
```

#### Change 10.3 — Remove LUKS reference in volatile journal comment

**Before:**
```nix
# ── Volatile systemd journal ────────────────────────────────────────────
# Logs are stored in RAM only and discarded on poweroff/reboot.
# This eliminates forensic log artefacts on the persistent volume and
# reduces writes to the LUKS-encrypted Btrfs partition.
```

**After:**
```nix
# ── Volatile systemd journal ────────────────────────────────────────────
# Logs are stored in RAM only and discarded on poweroff/reboot.
# This eliminates forensic log artefacts on the persistent volume and
# reduces writes to the persistent Btrfs partition.
```

---

## 5. Risk Analysis

### Risk 1 — `lib.mkDefault` conflict with existing `hardware-configuration.nix`

**Scenario:** A system that already has `hardware-configuration.nix` with `fileSystems` entries before migration. After regeneration via `--no-filesystems`, conflicting entries are removed, but if someone runs `nixos-rebuild switch` without the migration script (i.e., before subvolumes exist), the mkDefault fileSystems will point to a plain Btrfs root with a subvol that doesn't exist.

**Mitigation:** The migration script is the required first step. Documentation in `modules/stateless-disk.nix` and `modules/impermanence.nix` should make this clear. The impermanence assertion will catch the case where `/persistent` is not properly declared with `neededForBoot = true`.

**Residual risk:** Low — the assertion fails loudly at evaluation time with a descriptive message if the layout is wrong.

---

### Risk 2 — `cp --reflink=always` fails on non-Btrfs or cross-filesystem copy

**Scenario:** The migration script uses `--reflink=always`. If `/nix` and the Btrfs root partition are on different filesystems (e.g., `/nix` is on a separate ext4 partition), reflink will fail.

**Mitigation:** The script verifies that root (`/`) is Btrfs before proceeding. This covers the common case where `/nix` is under `/` on the same Btrfs partition. If the user has a separate `/nix` partition, the script will fail at the fstype check versus `/`.

**Residual risk:** Low for the expected configuration. If a user has a non-standard layout, the script exits with a clear error before any destructive operations.

---

### Risk 3 — `nixos-generate-config --no-filesystems` produces unexpected output

**Scenario:** The `head -n -1` approach to stripping the final `}` from `hardware-configuration.nix` before appending assumes the file ends with a single `}` on its own line. If `nixos-generate-config` produces a file that ends differently (e.g., comments after the final brace), the append could produce invalid Nix.

**Mitigation:** After the migration script runs `nixos-generate-config`, the appended content is validated implicitly at the `nixos-rebuild switch` step, which evaluates the Nix file and will report a parse error immediately. The backup at `.pre-stateless` allows recovery.

**Residual risk:** Low — `nixos-generate-config` consistently produces a trailing `}` as its last non-empty line. The safety check for file existence before appending catches the pathological missing-file case.

---

### Risk 4 — disko still referenced via `nix run` in `stateless-setup.sh`

**Scenario:** After removing disko as a flake input, the setup script still runs:
```bash
sudo nix run 'github:nix-community/disko/latest' -- ...
```
This fetches disko directly from GitHub, bypassing the flake lock.

**Mitigation:** This is intentional and correct. The disko CLI is a formatting tool, not a NixOS module dependency. Fetching it ad-hoc during initial setup is the expected usage pattern for disko. The flake lock is not involved in ad-hoc `nix run` invocations.

**Residual risk:** Negligible — disko CLI changes are forward-compatible with the `diskoFile ? null` fix applied to the template.

---

### Risk 5 — Stale disko lockfile entry after removing the input

**Scenario:** After removing the `disko` input from `flake.nix`, the `flake.lock` will still contain a `disko` entry until `nix flake update` or `nix flake lock --update-input disko` is run (or the lock is regenerated). This is harmless but produces a warning.

**Mitigation:** The implementation phase should run `nix flake lock` after modifying `flake.nix` to clean up the lockfile. Alternatively, manually remove the `disko` node from `flake.lock`. Include this step in the implementation instructions.

**Residual risk:** Very low — stale lockfile entries are warned about but do not prevent evaluation.

---

### Risk 6 — `nixosModules.statelessBase` consumed by `template/etc-nixos-flake.nix`

**Scenario:** The thin host wrapper at `template/etc-nixos-flake.nix` uses `vexos-nix.nixosModules.statelessBase`. After removing disko from `statelessBase`, any host currently using this wrapper with a disko-dependent assumption will work correctly (no change to the wrapper itself is needed — disko was invisible to it).

**Mitigation:** The wrapper is a template document. Users who have deployed it will receive the updated `statelessBase` on next `nixos-rebuild switch` via the flake fetch. No host-side changes are required.

**Residual risk:** None — removing the disko import from statelessBase is additive-safe for existing deployments.

---

## Appendix A — File Change Summary

| File | Change Type | Key Change |
|---|---|---|
| `flake.nix` | Modify | Remove disko input, remove disko from 4 stateless configs + statelessBase + statelessGpuVm |
| `modules/stateless-disk.nix` | Rewrite config block | Replace disko.devices with direct fileSystems using lib.mkDefault; remove enableLuks/luksName/memorySize options |
| `template/stateless-disko.nix` | Modify signature + header | Add `diskoFile ? null`; change `enableLuks` default to `false`; update comments |
| `hosts/stateless-amd.nix` | No change | enableLuks not present; no modification needed |
| `hosts/stateless-nvidia.nix` | No change | enableLuks not present; no modification needed |
| `hosts/stateless-intel.nix` | No change | enableLuks not present; no modification needed |
| `hosts/stateless-vm.nix` | Modify | Remove `enableLuks = false` |
| `scripts/stateless-setup.sh` | Modify | Remove LUKS conditional, set LUKS_BOOL="false"; update hostname default; remove LUKS warning |
| `scripts/migrate-to-stateless.sh` | **NEW FILE** | In-place migration script: subvol creation, reflink copy, hw-config update, nixos-rebuild |
| `modules/impermanence.nix` | Modify comments | Update header; update assertion message; remove "LUKS-encrypted" from journal comment |
| `flake.lock` | Modify | Remove disko node after running `nix flake lock` |

---

## Appendix B — Verification Steps for Implementation Phase

After implementing all changes, the implementation agent must verify:

1. `nix flake check` passes with no evaluation errors
2. `nix eval .#nixosConfigurations.vexos-stateless-amd.config.fileSystems` shows `/boot`, `/nix`, `/persistent` without referencing disko
3. `grep -r "disko" flake.nix` returns no results (other than possibly a comment)
4. `grep -r "enableLuks" modules/stateless-disk.nix` returns no results
5. `grep -r "enableLuks" hosts/stateless-vm.nix` returns no results
6. `bash -n scripts/migrate-to-stateless.sh` — bash syntax check passes
7. `bash -n scripts/stateless-setup.sh` — bash syntax check passes
8. The `flake.lock` file does not contain a `disko` node
