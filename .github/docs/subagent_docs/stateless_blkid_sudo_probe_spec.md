# Phase 1 Spec — stateless_blkid_sudo_probe

## Problem Definition

`blkid -p -s UUID -o value /dev/disk/by-partlabel/disk-main-ESP` still returns empty
after the previous fix added `-p`. The install fails on real hardware with:

```
ERROR: Could not read UUID for EFI partition (disk-main-ESP).
  Verify the partition exists: blkid /dev/disk/by-partlabel/disk-main-ESP
```

## Root Cause Analysis

Two independent problems exist for the ESP (vfat), only one for the root partition (btrfs):

### Problem A — vfat does not trigger a udev re-probe event after mkfs (cache miss)

After `mkfs.vfat` writes the FAT32 filesystem to `/dev/sda1`:
- The FAT format is done entirely in userspace; no kernel module is involved.
- No `KOBJ_CHANGE` uevent is sent to udev for the block device.
- Udev's `60-block.rules` never runs `blkid --probe /dev/sda1`.
- The blkid cache at `/run/blkid/blkid.tab` has NO entry for the new ESP UUID.

After `mkfs.btrfs` writes to `/dev/sda2`:
- The btrfs kernel module is involved and sends a uevent.
- Udev runs blkid as root and populates the cache with UUID `1e55d340-...`.
- `blkid -s UUID -o value` (without `-p`) reads this cache entry and succeeds.

This is why ROOT_UUID works without `-p` but BOOT_UUID does not.

### Problem B — raw device read requires root; live ISO user is unprivileged for storage

`blkid -p` bypasses the cache and reads the raw block device directly.
Reading `/dev/sda1` requires read permission on the block device.

On NixOS live ISO, block devices have permissions `brw-rw---- root:disk`.
The `nixos` user is in `wheel` but NOT in `disk` — storage devices are not granted
via `uaccess` (that is reserved for seat-specific peripherals like audio/video/input).

When `blkid -p /dev/disk/by-partlabel/disk-main-ESP` runs as `nixos`:
- Resolves the symlink to `/dev/sda1`
- Attempts `open("/dev/sda1", O_RDONLY)` → EACCES (no disk group membership)
- Prints error to stderr → suppressed by `2>/dev/null`
- Returns non-zero → suppressed by `|| true`
- Result: empty string

ROOT_UUID does NOT hit this path because the blkid cache already has the btrfs UUID
(Problem A doesn't apply to btrfs), so blkid reads the cache file — which IS readable
by the `nixos` user — without needing to open the raw device.

## Two-Problem Summary

| | ESP (vfat) | Root (btrfs) |
|---|---|---|
| Cache populated after mkfs? | No — vfat has no udev event | Yes — btrfs uevent triggers blkid as root |
| Direct probe possible as nixos? | No — EACCES on /dev/sda1 | Not needed (cache hit) |
| blkid -s UUID works? | **No** | Yes |
| blkid -p works as nixos? | **No** (EACCES) | Not tested (cache bypass); may also fail |

## Solution

Replace `blkid -p -s UUID -o value` with `sudo blkid -p -s UUID -o value` for both calls.

- `sudo` → runs as root, always has read access to block devices → solves Problem B
- `-p` → bypasses the stale blkid cache → solves Problem A
- Together: root-level direct probe always returns the correct UUID regardless of udev
  event state or cache state

Also update the error-message debugging hints to use `sudo blkid` (without it the nixos
user would get the same EACCES failure when trying to diagnose manually).

## Affected Files

- `scripts/stateless-setup.sh` — add `sudo` to both `blkid -p` calls; update hints

## Implementation Steps

1. Edit `scripts/stateless-setup.sh`:
   - Lines 246-247: change `blkid -p` to `sudo blkid -p`
   - Lines 250, 255: update debugging hints from `blkid ...` to `sudo blkid ...`
   - Update comment to explain both the cache miss and the permission requirement

## Dependencies

No new dependencies. `sudo` is always available on NixOS live ISO.

## Risks and Mitigations

- **Risk:** `sudo blkid -p` on a mounted FAT32 device corrupts data.
  **Mitigation:** blkid `-p` is strictly read-only. It reads only the first sector of
  the BPB to extract the volume serial number. No writes occur.

- **Risk:** `sudo` is unavailable (non-live installation scenario).
  **Mitigation:** The script already uses `sudo` extensively throughout (nixos-generate-config,
  git, curl to /mnt, tee). If sudo is unavailable, the entire script fails much earlier.
