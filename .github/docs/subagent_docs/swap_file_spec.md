# Specification: Add 8GB Swap File to vexos-nix
**Feature:** `swap_file`  
**Date:** 2026-04-08  
**Author:** Research & Specification Subagent

---

## 1. Current State Analysis

### 1.1 Existing Swap Configuration

Currently, the project configures **only ZRAM swap** in `modules/performance.nix`:

```nix
zramSwap = {
  enable = true;
  algorithm = "lz4";
  memoryPercent = 50; # up to 50% of physical RAM as compressed swap
};
```

There are **no swapDevices configured** anywhere in the project — confirmed by searching all `.nix` files for `swapDevices`, `swapfile`, and `swap.nix`.

`vm.swappiness` is also set to `10` in `performance.nix`, appropriate for a gaming workload with disk-based swap as a fallback.

### 1.2 Module Architecture

- `configuration.nix` — top-level module that imports all shared modules; all hosts import this
- `modules/system.nix` — uses the `vexos.btrfs.enable` option pattern (bool, default `true`) to conditionally apply btrfs features
- `hosts/vm.nix` — explicitly sets `vexos.btrfs.enable = false` to skip btrfs tooling for VM guests
- `hosts/amd.nix`, `hosts/nvidia.nix`, `hosts/intel.nix` — bare-metal hosts; import `configuration.nix` plus a GPU module
- **No swap module exists yet**

### 1.3 Filesystem Context

- Bare-metal hosts (`amd`, `nvidia`, `intel`): assumed **btrfs** root (`system.nix` enables snapper, auto-scrub, and btrfs-assistant by default)
- VM guest (`vm`): ext4/xfs, btrfs disabled (`vexos.btrfs.enable = false`)

---

## 2. Problem Definition

A pure ZRAM swap setup compresses unused pages in-RAM, which helps when RAM is underutilised, but provides **no overflow beyond physical RAM**. On a desktop gaming system, large workloads (e.g., compiling, Steam compat layer, big game assets in memory) can exhaust both physical RAM and ZRAM headroom simultaneously. A persistent disk-backed swap file provides:

1. **True overflow capacity** — when RAM + ZRAM are exhausted, the kernel can page out to disk instead of OOM-killing processes
2. **Hibernation compatibility** — a disk swap file is required for system hibernate/resume (not possible with ZRAM-only)
3. **Stability under memory pressure** — prevents kernel OOM panics during large build jobs or memory spikes

The request is for an **8 GiB swap file** to be added declaratively via NixOS configuration.

---

## 3. Research Findings

### Source 1 — NixOS Wiki: Swap
`https://nixos.wiki/wiki/Swap`

The canonical NixOS swap option is `swapDevices`. When `size` is set (in MiB), NixOS automatically creates the file:

```nix
swapDevices = [{
  device = "/var/lib/swapfile";
  size = 16*1024;  # 16 GiB example; 8*1024 for 8 GiB
}];
```

`size` is interpreted as MiB (1024×1024 bytes). 8 GiB = **8192 MiB**.

### Source 2 — NixOS Options Reference (nixos-25.11)
`https://search.nixos.org/options?channel=25.11&query=swapDevices`

Key options confirmed:
| Option | Type | Description |
|--------|------|-------------|
| `swapDevices.*.device` | `nonEmptyStr` | Path to swap file or block device |
| `swapDevices.*.size` | `null or int` | Size in MiB; causes NixOS to auto-create the file |
| `swapDevices.*.randomEncryption.enable` | `bool` | Encrypt swap with a random key on each boot |
| `swapDevices.*.priority` | `null or int` | Kernel swap priority (0–32767; null = negative, auto) |
| `swapDevices.*.options` | `listOf nonEmptyStr` | mount options (default `["defaults"]`) |

### Source 3 — nixpkgs source: `nixos/modules/config/swap.nix` (nixos-25.11)
`https://github.com/NixOS/nixpkgs/blob/nixos-25.11/nixos/modules/config/swap.nix`

Critical implementation detail: when `size != null`, `swap.nix` creates the swapfile via a systemd oneshot service `mkswap-<deviceName>`. The service is **btrfs-aware** as of nixpkgs 25.11:

```bash
if [[ $(stat -f -c %T $(dirname "$DEVICE")) == "btrfs" ]]; then
  # Use btrfs filesystem mkswapfile — handles NODATACOW automatically
  rm -f "$DEVICE"
  btrfs filesystem mkswapfile --size "${size}M" --uuid clear "$DEVICE"
else
  truncate --size 0 "$DEVICE"
  chattr +C "$DEVICE" 2>/dev/null || true
  dd if=/dev/zero of="$DEVICE" bs=1M count=${size} status=progress
  mkswap "$DEVICE"
fi
```

This means **no manual btrfs workarounds are required** — nixpkgs handles NODATACOW and proper mkswapfile creation transparently.

### Source 4 — NixOS Wiki: Btrfs — Swap file section
`https://wiki.nixos.org/wiki/Btrfs#Swap_file`

The wiki confirms the NixOS-native approach:

```nix
swapDevices = [{
  device = "/swap/swapfile";
  size = 8*1024;  # 8 GiB
}];
```

**Critical btrfs constraint**: A btrfs subvolume **cannot be snapshotted** while it contains an active swapfile. If the swapfile resides in the root subvolume (`@`) and snapper snapshots `/`, snapper will fail while swap is active.

**Mitigation**: Use a dedicated btrfs swap subvolume (e.g., `/swap`) that snapper does NOT snapshot. The `swapDevices.*.device` path should be `/swap/swapfile` and the `/swap` mount point must be on its own btrfs subvolume in `hardware-configuration.nix`.

However, since `hardware-configuration.nix` is not tracked in this repo, the spec documents this constraint and provides a safe default (`/var/lib/swapfile`) with documentation directing users to create a dedicated subvolume.

### Source 5 — btrfs documentation: Swapfile
`https://btrfs.readthedocs.io/en/latest/Swapfile.html`

Btrfs swapfile requirements:
- Filesystem must be single-device
- Filesystem must have single data profile
- Swapfile must be preallocated (no holes)
- Swapfile must have NODATACOW set (no compression, no checksums)
- **Active swapfile prevents snapshotting of the containing subvolume**

All of the above are automatically satisfied by nixpkgs `swap.nix` using `btrfs filesystem mkswapfile`.

### Source 6 — ZRAM vs Swapfile: Complementary use
ZRAM and a swapfile serve complementary roles and are NOT mutually exclusive:

| | ZRAM | Swapfile |
|--|------|----------|
| Storage | Compressed in-RAM | On-disk |
| Speed | Very fast (RAM speed) | Slow (disk I/O) |
| Size limit | Fraction of RAM (50% here) | Arbitrary (8 GiB) |
| Overflow beyond RAM | No | Yes |
| Hibernate support | No | Yes |
| Kernel uses first? | Yes (higher priority) | No (lower priority, `vm.swappiness=10`) |

With `vm.swappiness = 10` already set, the kernel will strongly prefer keeping pages in RAM and ZRAM before touching the swap file. The disk swap file is a last-resort safety net.

### Source 7 — randomEncryption consideration
`swapDevices.*.randomEncryption.enable = true` encrypts the swap file with a random key on each boot, preventing forensic recovery of swap contents. **However:**
- `WARNING: Do not hibernate with randomEncryption enabled` — the saved image is unreadable on resume
- Does not apply to file-backed swap on an already-LUKS-encrypted disk (double-encryption adds overhead with no benefit)
- Incompatible with devices identified by UUID or label

**Decision**: `randomEncryption.enable` is **not set** (defaults `false`) to preserve hibernation capability and avoid LUKS interaction complexity.

---

## 4. Proposed Solution Architecture

### 4.1 New Module: `modules/swap.nix`

Create a dedicated swap module following the established `vexos.*` option pattern (same as `vexos.btrfs.enable` in `system.nix`):

```nix
# modules/swap.nix
{ lib, config, ... }:
let
  cfg = config.vexos.swap;
in
{
  options.vexos.swap.enable = lib.mkOption {
    type    = lib.types.bool;
    default = true;
    description = ''
      Enable an 8 GiB disk-backed swap file at /var/lib/swapfile.
      Acts as overflow beyond ZRAM capacity and enables hibernation support.
      Set to false on VM guests where the hypervisor manages memory limits.

      BTRFS NOTE: If your root filesystem is btrfs and you have snapper enabled,
      place the swapfile on a dedicated btrfs subvolume (e.g. mounted at /swap)
      instead of within the root subvolume (@). The subvolume containing an
      active swapfile cannot be snapshotted. Update swapDevices.device in this
      module to /swap/swapfile and add a /swap mount to hardware-configuration.nix.
    '';
  };

  config = lib.mkIf cfg.enable {
    swapDevices = [
      {
        device = "/var/lib/swapfile";
        size   = 8192; # 8 GiB in MiB (8 × 1024)
        # randomEncryption deliberately omitted:
        # enabling it prevents hibernation and has no benefit on LUKS-encrypted drives.
      }
    ];
  };
}
```

### 4.2 Import in `configuration.nix`

Add `./modules/swap.nix` to the `imports` list in `configuration.nix`.

### 4.3 Disable in `hosts/vm.nix`

VM guests do not need a disk swap file — the hypervisor allocates and manages memory, and the guest kernel can be killed by the host OOM manager instead. Adding:

```nix
vexos.swap.enable = false;
```

to `hosts/vm.nix`, analogous to the existing `vexos.btrfs.enable = false`.

---

## 5. Implementation Steps

### Step 1: Create `modules/swap.nix`

Create the file with the following exact content:

```nix
# modules/swap.nix
# Disk-backed swap file (8 GiB) — complements ZRAM swap as a last-resort
# overflow and enables hibernation support on bare-metal hosts.
#
# BTRFS + SNAPPER NOTE:
#   An active swapfile prevents btrfs from snapshotting the subvolume that
#   contains it. If /var/lib is within your root subvolume (@), snapper will
#   fail to snapshot / while this swap is active.
#
#   Recommended fix (done in hardware-configuration.nix, not this repo):
#     1. Create a btrfs subvolume, e.g.:  btrfs subvolume create /mnt/swap
#     2. Mount it at /swap with option noatime
#     3. Change device below to "/swap/swapfile"
#   This module defaults to /var/lib/swapfile for zero-config activation.
{ lib, config, ... }:
let
  cfg = config.vexos.swap;
in
{
  options.vexos.swap.enable = lib.mkOption {
    type        = lib.types.bool;
    default     = true;
    description = ''
      Enable an 8 GiB disk-backed swap file at /var/lib/swapfile.
      NixOS creates and initialises the file automatically (btrfs-aware:
      uses btrfs filesystem mkswapfile when the parent directory is btrfs).
      Set to false on VM guests where the hypervisor manages memory limits.
    '';
  };

  config = lib.mkIf cfg.enable {
    swapDevices = [
      {
        device = "/var/lib/swapfile";
        size   = 8192; # MiB — 8 GiB (8 × 1024)
      }
    ];
  };
}
```

### Step 2: Add import to `configuration.nix`

In the `imports` list inside `configuration.nix`, append:

```nix
./modules/swap.nix
```

alongside the other module imports.

### Step 3: Disable swap in `hosts/vm.nix`

Add `vexos.swap.enable = false;` to `hosts/vm.nix`:

```nix
# hosts/vm.nix
{ inputs, ... }:
{
  imports = [
    ../configuration.nix
    ../modules/gpu/vm.nix
  ];

  networking.hostName = "vexos-desktop-vm";

  # VM guests use ext4/xfs — no btrfs tooling needed.
  vexos.btrfs.enable = false;

  # VM guests do not need a persistent swap file;
  # the hypervisor manages guest memory limits.
  vexos.swap.enable = false;

  environment.systemPackages = [
    inputs.up.packages.x86_64-linux.default
  ];
}
```

---

## 6. File Modification Summary

| File | Action | Notes |
|------|--------|-------|
| `modules/swap.nix` | **CREATE** | New module; 8 GiB swapfile, `vexos.swap.enable` option |
| `configuration.nix` | **MODIFY** | Add `./modules/swap.nix` to imports |
| `hosts/vm.nix` | **MODIFY** | Add `vexos.swap.enable = false` |

`hosts/amd.nix`, `hosts/nvidia.nix`, and `hosts/intel.nix` require **no changes** — `vexos.swap.enable` defaults to `true`, so bare-metal hosts automatically get the swap file.

---

## 7. Risks and Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| **btrfs swapfile + snapper conflict** — active swapfile in root subvolume prevents snapper snapshots of `/` | High | Document clearly in module comment. Users should create a dedicated `/swap` btrfs subvolume in `hardware-configuration.nix` and update `device` to `/swap/swapfile`. nixpkgs handles NODATACOW automatically either way. |
| **Swapfile creation time on first rebuild** — `dd` of 8 GiB may take 30–120 s on a spinning HDD | Low | NixOS creates it via a oneshot systemd service at boot, not during rebuild. btrfs uses `mkswapfile` which is faster than `dd`. |
| **Disk space consumption** — 8 GiB reserved on root / partition | Low | Documented. Users with <16 GiB free should reduce `size` or skip the module. |
| **randomEncryption + hibernation incompatibility** | Avoided | `randomEncryption` left at default `false`. Documented in module source comment. |
| **VM guests activating swap unnecessarily** | Avoided | `vexos.swap.enable = false` explicitly set in `hosts/vm.nix`. |
| **ZRAM + swapfile priority mismatch** — kernel could use disk swap before ZRAM | Mitigated | `vm.swappiness = 10` in `performance.nix` already strongly discourages early swapping. ZRAM auto-registers at a higher kernel priority than file-backed swap, so this ordering is maintained automatically. |
| **swapfile path not writable at boot** — `/var/lib` may not exist early | Low | `/var/lib` is always available on NixOS by the time systemd runs the `mkswap-*` service (it has explicit `RequiresMountsFor` in the generated unit). |

---

## 8. Validation Criteria

After implementation, the following must pass:

1. `nix flake check` — all four outputs evaluate without errors
2. `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd` — AMD closure builds
3. `sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia` — NVIDIA closure builds
4. `sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm` — VM closure builds (swap disabled)
5. `sudo nixos-rebuild dry-build --flake .#vexos-desktop-intel` — Intel closure builds

On a live system after rebuild:
- `swapon --show` should list `/var/lib/swapfile` as `file` type, `8G` size, alongside the ZRAM device
- `ls -lh /var/lib/swapfile` should show the file at 8 GiB

---

## 9. Sources Referenced

1. NixOS Wiki — Swap: https://nixos.wiki/wiki/Swap
2. NixOS Wiki — Btrfs / Swap file: https://wiki.nixos.org/wiki/Btrfs#Swap_file
3. nixpkgs source — `nixos/modules/config/swap.nix` (nixos-25.11): https://github.com/NixOS/nixpkgs/blob/nixos-25.11/nixos/modules/config/swap.nix
4. btrfs documentation — Swapfile: https://btrfs.readthedocs.io/en/latest/Swapfile.html
5. NixOS Options search — `swapDevices` (channel 25.11): https://search.nixos.org/options?channel=25.11&query=swapDevices
6. ZRAM complementary use analysis — derived from `zramSwap` NixOS option documentation and `vm.swappiness` kernel parameter behaviour
