# Phase 1 Spec — stateless_setup_uuid_race

## Problem Definition

After a completed `stateless-setup.sh` install, the system enters Stage 2 emergency mode
on every boot. `journalctl` shows a 90-second timeout on a device unit, and
`cat /etc/nixos/hardware-configuration.nix` (read from the emergency shell) confirms:

```nix
fileSystems."/boot" = {
  device  = "/dev/disk/by-uuid/";   # ← UUID is EMPTY — invalid device path
  fsType  = "vfat";
  options = [ "fmask=0077" "dmask=0077" ];
};
```

The `/nix` and `/persistent` entries have the correct UUID. Only the ESP (boot) entry
is broken.

**This is a general bug affecting all hardware — not VM-specific.**

## Root Cause Analysis

`stateless-setup.sh` lines 214-215 (after disko formats and mounts the disk):

```bash
BOOT_UUID=$(blkid -s UUID -o value /dev/disk/by-partlabel/disk-main-ESP)
ROOT_UUID=$(blkid -s UUID -o value /dev/disk/by-partlabel/disk-main-data)
```

Two problems:

### Problem 1 — Race condition: udev/blkid cache may not yet reflect the formatted ESP

After disko completes, kernel partition events are pending. Udev creates
`/dev/disk/by-partlabel/disk-main-ESP` shortly after, and the blkid cache is updated
when udev processes the `FORMAT` event for the new FAT32 filesystem.

If `blkid -s UUID -o value` runs before udev has processed that event, the blkid cache
entry for the ESP either doesn't exist yet or contains the pre-format state (no UUID).
`blkid` exits 0 with empty output in this case (device readable, but UUID attribute not
found in cache or superblock read). With `set -euo pipefail`, an empty-string assignment
does NOT abort the script — so execution continues with `BOOT_UUID=""`.

`ROOT_UUID` succeeds because btrfs UUID assignment differs from FAT32 and udev processes
the btrfs `FORMAT` event first, or the btrfs superblock is more reliably read directly.

### Problem 2 — No validation of empty UUIDs

The script writes hardware-configuration.nix immediately after capture, with no check
whether `BOOT_UUID` is empty. An empty `BOOT_UUID` produces:

```nix
device = "/dev/disk/by-uuid/";
```

This is a directory, not a block device. Systemd creates a device unit for it,
waits the default 90 seconds for the device to appear, times out, and marks
`/boot.mount` as failed. Because `/boot.mount` is a required dependency of
`local-fs.target`, which is required by `multi-user.target`, the failure propagates and
Stage 2 drops to emergency mode.

## Prior Art — migrate-to-stateless.sh Already Has the Guard

`scripts/migrate-to-stateless.sh` lines 114-124 already apply the correct pattern:

```bash
ROOT_UUID=$(blkid -s UUID -o value "$ROOT_DEV_RAW" 2>/dev/null || true)
BOOT_UUID=$(blkid -s UUID -o value "$BOOT_DEVICE" 2>/dev/null || true)

if [ -z "$ROOT_UUID" ]; then
  echo -e "${RED}Could not determine UUID for root device: ${ROOT_DEV_RAW}${RESET}"
  exit 1
fi
if [ -z "$BOOT_UUID" ]; then
  echo -e "${RED}Could not determine UUID for boot device: ${BOOT_DEVICE}${RESET}"
  exit 1
fi
```

The fix for `stateless-setup.sh` must match this pattern, with an additional
`udevadm settle` before the captures (since `stateless-setup.sh` runs immediately
after disko, while `migrate-to-stateless.sh` runs on an already-partitioned system).

## Affected Files

- `scripts/stateless-setup.sh` — missing `udevadm settle` and missing empty-UUID validation

## Proposed Solution

In `scripts/stateless-setup.sh`, between the disko run and the `blkid` calls:

1. Add `udevadm settle --timeout=30` to wait for udev to process all disko-generated
   partition and format events before querying the blkid cache.

2. Add `2>/dev/null || true` to each blkid call to prevent accidental `set -e` abort
   (matching `migrate-to-stateless.sh` style).

3. Add non-empty validation for both `BOOT_UUID` and `ROOT_UUID` immediately after
   capture, with clear error messages that include the partition path to aid debugging.

### Updated code block (lines 212-215 replacement)

```bash
# Wait for udev to process all disko partition/format events before querying UUIDs.
# Without this, blkid may read a stale cache entry for the freshly-formatted ESP
# and return an empty UUID — which produces an invalid device path in
# hardware-configuration.nix ("/dev/disk/by-uuid/") and causes a 90-second boot
# timeout followed by Stage 2 emergency mode.
udevadm settle --timeout=30

BOOT_UUID=$(blkid -s UUID -o value /dev/disk/by-partlabel/disk-main-ESP 2>/dev/null || true)
ROOT_UUID=$(blkid -s UUID -o value /dev/disk/by-partlabel/disk-main-data 2>/dev/null || true)

if [ -z "$BOOT_UUID" ]; then
  echo -e "${RED}ERROR: Could not read UUID for EFI partition (disk-main-ESP).${RESET}"
  echo "  Verify the partition exists: blkid /dev/disk/by-partlabel/disk-main-ESP"
  exit 1
fi
if [ -z "$ROOT_UUID" ]; then
  echo -e "${RED}ERROR: Could not read UUID for root partition (disk-main-data).${RESET}"
  echo "  Verify the partition exists: blkid /dev/disk/by-partlabel/disk-main-data"
  exit 1
fi
```

## Implementation Steps

1. Edit `scripts/stateless-setup.sh`:
   - Replace lines 212-215 (the comment + two blkid calls) with the block above

## Dependencies

No new external dependencies. Uses `udevadm` (always present in NixOS live ISO).

## Context7

Not required — no external libraries involved.

## Risks and Mitigations

- **Risk:** `udevadm settle --timeout=30` may hang on a system with udev storm.
  **Mitigation:** The 30-second timeout ensures the script eventually continues or
  fails. Any system that takes >30 seconds to settle after a disk format has a deeper
  hardware/driver issue beyond this script's scope.

- **Risk:** blkid still returns empty after `udevadm settle` (e.g. faulty disk).
  **Mitigation:** The new validation aborts with a clear error message and a debugging
  command hint, so the operator knows exactly what to check instead of getting a
  silently-broken install.

- **Risk:** This is a bash-only fix; the comment at line 212 claims "always available
  after disko runs sgdisk + udevadm settle" — this was incorrect.
  **Mitigation:** The comment is updated to accurately describe the new, explicit settle.
