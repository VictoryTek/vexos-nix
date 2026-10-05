# ZFS pool topology menu — plain-language wording (spec)

## Current state
`scripts/create-zfs-pool.sh` step [3/8] shows a topology menu using ZFS jargon
(`single`, `mirror`, `raidz1`, `raid10`, "single parity", "stripe of mirrors").
It never states usable capacity or how many disks can fail.

## Problem
A user selected option 2 ("mirror — 2+ disks (RAID1)") with three 500 GB disks expecting
1.5 TB and got 500 GB: a ZFS mirror vdev keeps a full copy on every disk, so capacity
equals one disk. The menu gave no hint of this.

Two further label inaccuracies versus the code:
- Option 1 "single — 1 disk": the script only enforces `MIN_DISKS=1`, so selecting N disks
  runs `zpool create pool d1 d2 … dN` — a stripe (capacity = sum of disks, zero
  redundancy, any single disk failure loses the pool). The label implies exactly one disk.
- Option 6 "4/6/8 disks": code only requires an even count >= 4 (lines 177-180).

## Proposed change (text only — no behavioural change)
Rewrite the menu echo lines and hint in step [3/8] so each option states, in plain words:
what it does, minimum disks, usable space (with a 3 x 500 GB style example), and how many
disk failures it survives. Option numbers, `TOPO` values, `MIN_DISKS` values, the `case`
mapping and all later logic stay identical.

Option 1 is labelled by what it actually does today (all disks added together, no
protection) rather than changing enforcement. Tightening it to exactly one disk is a
behaviour change that was not requested and is left to the user.

Capacity facts (standard OpenZFS semantics, N = disks, equal-size disks assumed):
- stripe: N disks usable, 0 failures survived
- mirror: 1 disk usable, N-1 failures survived
- raidz1/2/3: N-1 / N-2 / N-3 usable, 1 / 2 / 3 failures survived
- raid10 (striped mirror pairs): N/2 usable, 1 failure per pair survived

## Implementation steps
1. Edit lines 76-86 of `scripts/create-zfs-pool.sh` (menu text + hint only).
2. Option B module rules / Nix evaluation are unaffected (shell script, not a module).

## Dependencies
None. No Context7 lookup required (no new libraries).

## Risks and mitigations
- Echo text only; `bash -n` plus preflight confirm syntax and that no Nix output changed.
- Wording must not overclaim: usable space is approximate (smallest disk governs; ZFS
  metadata overhead) — stated in the menu.
