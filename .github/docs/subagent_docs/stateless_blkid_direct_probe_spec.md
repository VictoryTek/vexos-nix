# Phase 1 Spec — stateless_blkid_direct_probe

## Problem Definition

After the `stateless_setup_uuid_race` fix (adding `udevadm settle + empty-UUID
validation`), the install still fails on real hardware:

```
ERROR: Could not read UUID for EFI partition (disk-main-ESP).
  Verify the partition exists: blkid /dev/disk/by-partlabel/disk-main-ESP
```

`BOOT_UUID` is still empty. `udevadm settle` does not help.

## Root Cause Analysis

The disko trace reveals the ordering:

```
+ udevadm trigger --subsystem-match=block
+ udevadm settle --timeout 120       ← disko settles BEFORE mkfs.vfat
+ ...
+ mkfs.vfat /dev/disk/by-partlabel/disk-main-ESP    ← format happens AFTER settle
+ mkfs.btrfs /dev/disk/by-partlabel/disk-main-data -f
...
+ mount /dev/disk/by-partlabel/disk-main-ESP /mnt/boot ...
+ mount /dev/disk/by-partlabel/disk-main-data /mnt/nix ...
+ mount /dev/disk/by-partlabel/disk-main-data /mnt/persistent ...
                                    ← disko exits. NO udevadm trigger/settle after mkfs.
```

Disko's `udevadm settle` runs after partprobe (to ensure the partlabel symlinks exist),
but BEFORE `mkfs.vfat`. After formatting the ESP, disko does NOT call `udevadm trigger`
or `udevadm settle` again — it proceeds directly to mounting via partlabel.

**Consequence:**
After disko exits, udev has NOT been notified that `/dev/sda1` now contains a new FAT32
filesystem. The blkid cache at `/run/blkid/blkid.tab` has either:
- An entry from the pre-format state (no UUID, because wipefs erased the FAT32 magic), OR
- No entry for sda1 at all

Our `udevadm settle --timeout=30` waits for pending udev events. Since udev was never
triggered for the format event, there are ZERO pending events — settle returns
immediately, having accomplished nothing for the blkid cache.

`blkid -s UUID -o value /dev/disk/by-partlabel/disk-main-ESP`:
1. Checks the cache → finds no UUID (stale/empty entry)
2. Attempts direct probe → returns empty (on some systems, blkid avoids probing
   mounted devices in non-probe mode to prevent cache/race issues)
3. Returns exit 0 with empty output

`ROOT_UUID` is NOT affected because: (a) btrfs has additional udev rules that trigger
blkid probing on creation, OR (b) the btrfs UUID was already probed by a different
code path. Either way, the btrfs entry lands in the blkid cache reliably.

## Solution

Replace `blkid -s UUID -o value` with `blkid -p -s UUID -o value` for both captures.

The `-p` / `--probe` flag forces blkid to probe the device DIRECTLY from disk,
bypassing the blkid cache entirely. It reads the FAT32 Volume Serial Number (UUID)
from the raw block device at the hardware-assigned offset in the BPB, regardless of
whether the cache knows about the format event or not.

```bash
BOOT_UUID=$(blkid -p -s UUID -o value /dev/disk/by-partlabel/disk-main-ESP 2>/dev/null || true)
ROOT_UUID=$(blkid -p -s UUID -o value /dev/disk/by-partlabel/disk-main-data 2>/dev/null || true)
```

`blkid -p` on a mounted device is safe — it reads the raw device node, not through
the VFS. FAT32 probing reads only the BPB at sector 0, which is safe for a mounted
filesystem.

`udevadm settle --timeout=30` before these calls is retained: it still ensures the
partlabel symlinks (`/dev/disk/by-partlabel/disk-main-ESP`) exist and are resolvable
before blkid tries to open the device.

## Affected Files

- `scripts/stateless-setup.sh` — add `-p` to both `blkid` calls (lines 219-220)

## Implementation Steps

1. Edit `scripts/stateless-setup.sh` lines 219-220:
   - Change `blkid -s UUID -o value` to `blkid -p -s UUID -o value`

## Dependencies

No new dependencies. `blkid -p` is always available on NixOS live ISO.

## Risks and Mitigations

- **Risk:** `blkid -p` on a mounted FAT32 causes data corruption.
  **Mitigation:** blkid probing is strictly read-only. It reads the BPB sector to
  extract the volume serial number. No writes occur. This is safe.

- **Risk:** `blkid -p` returns a different output format than `blkid` (cached mode).
  **Mitigation:** The `-s UUID -o value` flags are fully compatible with probe mode
  and produce identical output (just the UUID string, no trailing newline from
  `$(...)`).
