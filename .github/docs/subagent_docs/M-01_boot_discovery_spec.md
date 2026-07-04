# M-01 — boot-discovery misses ESPs / silently fails to register them

Status: Phase 1 (Research & Specification)
Source: MASTER_PLAN M-01 · `modules/boot-discovery.nix` (read in full)

## Current State

The MASTER_PLAN's original description of this bug (`by-parttype/` being a
last-one-wins symlink) is **stale** — the module has already been rewritten since that
analysis to use `sfdisk --dump` directly on raw block devices, per its own header
comment, specifically to avoid udev/sysfs dependency issues found on NVMe drives. The
user reports the underlying symptom (systemd-boot never picking up an OS installed on a
separate physical drive during dual-boot) persists despite this rewrite, but live
diagnostics weren't available this session, so this fix is based on direct code review
of the current implementation rather than a captured failure log.

Two concrete defects found by tracing the script line by line:

1. **GPT-only ESP matching.** The match test is:
   ```bash
   [[ "${sline,,}" == *"type=$ESP_PARTTYPE"* ]] || continue
   ```
   where `ESP_PARTTYPE` is the GPT ESP GUID (`c12a7328-...`). `sfdisk --dump` reports a
   completely different `type=` value for MBR/DOS-labeled disks — a 2-hex-digit code,
   where the ESP type is `ef` (not a GUID at all). A disk with an MBR partition table
   (common on older installs, or disks partitioned by tools that default to MBR rather
   than GPT) has its ESP silently skipped — the substring `type=c12a7328-...` never
   appears in an MBR `sfdisk --dump` line. For a dual-boot setup with each OS on its own
   drive, it's entirely plausible one drive is GPT and another is MBR (e.g., an older
   Windows install, or an OS installed before the disk was ever repartitioned to GPT).

2. **Silent failure on `efibootmgr --create`.**
   ```bash
   efibootmgr --create --disk "$disk" --part "$part_num" --loader "$loader" \
     --label "$label" >/dev/null 2>&1 || true
   ```
   Any failure — wrong `--part` number, efivarfs not writable, `--disk`/`--part`
   mismatch, a malformed loader path, anything — is completely swallowed. The log only
   shows "registering: $label" before the call, never whether it actually succeeded.
   This means the exact symptom reported ("we've been trying to fix this for a while,
   it never works") could be caused by a real, fixable `efibootmgr` failure that has
   never once been visible in the journal, because `|| true` discards it unconditionally.

## Problem Definition

Make ESP discovery work for both GPT and MBR-labeled disks, and make registration
failures observable instead of silently discarded, so this can actually be debugged the
next time it doesn't work (rather than guessing again).

## Proposed Solution

1. Replace the loose substring match with precise `type=` field extraction that
   recognizes both the GPT ESP GUID and the MBR ESP type code (`ef`, case-insensitive):
   ```bash
   part_type="$(echo "$sline" | sed -n 's/.*type=\([^,]*\).*/\1/p' | tr '[:upper:]' '[:lower:]')"
   [[ "$part_type" == "$ESP_PARTTYPE" || "$part_type" == "ef" ]] || continue
   ```
2. Replace the blind `|| true` with an `if`/`else` that logs the actual outcome
   (capturing `efibootmgr`'s stdout+stderr and logging it on failure, logging
   confirmation on success):
   ```bash
   local out
   if out="$(efibootmgr --create --disk "$disk" --part "$part_num" \
              --loader "$loader" --label "$label" 2>&1)"; then
     log "registered: $label"
   else
     log "FAILED to register $label: $out"
   fi
   ```

## Implementation Steps

1. `modules/boot-discovery.nix` — both changes above, inside `discoveryScript`.

## Configuration Changes

None — no options, no flake changes, no new packages.

## Risks and Mitigations

- **No live hardware to test the actual dual-boot detection end-to-end** — mitigated by
  (a) `bash -n`/`shellcheck` on the extracted script, and (b) a standalone test harness
  simulating representative `sfdisk --dump` output for both GPT and MBR ESP lines to
  confirm the new matching logic parses each correctly, since I can't attach real disks
  in this sandbox.
- **This may not be the actual root cause on the user's system** — flagged explicitly:
  this is a code-review-based fix for two real defects found by inspection, not a
  confirmed fix for the user's specific failure (no journal log was available to
  confirm). If the problem persists after this, the next step would be capturing
  `journalctl -u vexos-boot-discovery -b` and `efibootmgr -v` output on the affected
  machine — now that failures are actually logged instead of swallowed, that log will be
  far more useful.
