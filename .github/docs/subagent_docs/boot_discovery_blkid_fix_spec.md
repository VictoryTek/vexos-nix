# Spec: Fix boot-discovery ESP detection via blkid

## Current State Analysis

`modules/boot-discovery.nix` discovers EFI System Partitions (ESPs) on secondary drives
using a glob over `/dev/disk/by-parttype/<ESP_GUID>*`. This relies on udev creating
partition-type symlinks in `/dev/disk/by-parttype/`.

**Root cause of failure:** `/dev/disk/by-parttype/` does not exist on this system.
The `for` loop expands to a literal string that fails `-e`, so `continue` fires immediately
and no ESPs are ever registered. The service exits 0 in ~11ms with no work done.

Confirmed via `ls /dev/disk/by-parttype/` → `No such file or directory`.

Disk layout (nvme0n1 — unregistered Windows drive):
- nvme0n1p1  100 MiB  → classic Windows ESP size
- nvme0n1p2   16 MiB  → Microsoft Reserved Partition
- nvme0n1p3  464.9 GiB → NTFS (Windows)
- nvme0n1p4  745 MiB  → Windows Recovery

## Problem Definition

The ESP discovery method assumes `by-parttype` symlinks exist. They do not, so the
feature is completely non-functional despite the service appearing healthy in `systemctl`.

## Proposed Solution

Replace the `/dev/disk/by-parttype/` glob with `blkid -c /dev/null -t PART_ENTRY_TYPE=...
-o device`. `blkid` probes partition tables directly from disk, bypassing udev symlink
state entirely. It is part of `util-linux`, which is already in the service's `path`.

### Changes Required

**`modules/boot-discovery.nix`** — ESP discovery loop only:

```
# OLD — relies on udev symlink directory
for esp_link in /dev/disk/by-parttype/${ESP_PARTTYPE}*; do
  [[ -e "$esp_link" ]] || continue
  esp_dev="$(readlink -f "$esp_link")"

# NEW — direct blkid probe, no udev dependency
for esp_dev in $(blkid -c /dev/null -t PART_ENTRY_TYPE="$ESP_PARTTYPE" -o device 2>/dev/null); do
  [[ -b "$esp_dev" ]] || continue
```

The `-c /dev/null` flag forces blkid to bypass its cache and probe live — this ensures
it sees disks even if udev hasn't settled or the cache is stale.

The rest of the script (lsblk PKNAME/PARTN/PARTUUID, mount, register) is unaffected.

## Implementation Steps

1. Edit `modules/boot-discovery.nix`: replace the `for esp_link` loop opener with
   the `for esp_dev` blkid form; remove the `readlink -f` line.
2. No package additions needed (`blkid` is in `util-linux`, already in `path`).

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| blkid not available in PATH | Already present via `util-linux` in `path` list |
| blkid subshell in for-loop (word splitting) | Acceptable: device paths from blkid contain no spaces; `-o device` outputs one path per line |
| Other drives with FAT32 but non-ESP partition type | blkid filter is by GPT type GUID, not filesystem — FAT32 data partitions with a different GUID are excluded |
| PARTUUID still empty after fix | lsblk already worked for PKNAME/PARTN; PARTUUID came from lsblk too and should be fine |
