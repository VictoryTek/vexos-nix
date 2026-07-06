# L-14 — Stale file-rename residue: deleted `performance.nix`, stale headers

Status: Phase 1 (Research & Specification)
Source: MASTER_PLAN L-14 (ARCH 2.4) · `modules/network.nix:3`,
`modules/gpu/vm.nix:10`, `modules/branding.nix:5`, `hosts/desktop-amd.nix:1`

## Current State

`modules/performance.nix` doesn't exist. Confirmed two real stale
references to it (grepped repo-wide for `performance\.nix`):
- `modules/network.nix:3` — "BBR TCP sysctl tuning is co-located with other
  kernel tunables in performance.nix." — BBR tuning (`tcp_congestion_control`)
  now actually lives in `modules/system.nix`.
- `modules/branding.nix:5` — "Plymouth enable is deliberately kept in
  modules/performance.nix." — `boot.plymouth.enable` now actually lives in
  `modules/system.nix` too.

**The plan's third citation is itself stale**: `modules/gpu/vm.nix:10` has
no reference to `performance.nix` at all — its only "performance" mention
(`powerManagement.cpuFreqGovernor = lib.mkForce "performance";`) is a
legitimate CPU governor name, not a stale file reference. Nothing to fix
there.

**Stale file headers** — checked every file under `hosts/` (24 files) for a
header comment matching its actual filename. Found exactly 4 mismatches,
all in the desktop role (apparently renamed from bare `hosts/<gpu>.nix` to
`hosts/desktop-<gpu>.nix` at some point, without updating their own header
comments) — the other 20 host files (headless-server, htpc, server,
stateless, vanilla) already have correct headers:
- `hosts/desktop-amd.nix` — header says `# hosts/amd.nix`
- `hosts/desktop-intel.nix` — header says `# hosts/intel.nix`
- `hosts/desktop-nvidia.nix` — header says `# hosts/nvidia.nix`
- `hosts/desktop-vm.nix` — header says `# hosts/vm.nix`

This is a superset of the plan's single cited example
(`hosts/desktop-amd.nix:1`) — all 4 desktop host files have the identical
stale-header pattern, so all 4 are fixed together for consistency.

## Problem Definition

Six total stale references: 2 pointing at a deleted file
(`modules/performance.nix`), 4 header comments naming the pre-rename
filename.

## Proposed Solution

Update each comment to the current, correct reference:
1. `modules/network.nix:3` — "performance.nix" → "system.nix".
2. `modules/branding.nix:5` — "performance.nix" → "system.nix".
3. The 4 desktop `hosts/*.nix` headers — match their actual filenames.

## Implementation Steps

1. `modules/network.nix` — fix comment.
2. `modules/branding.nix` — fix comment.
3. `hosts/desktop-amd.nix`, `hosts/desktop-intel.nix`,
   `hosts/desktop-nvidia.nix`, `hosts/desktop-vm.nix` — fix header comments.

## Configuration Changes

None — comment-only changes.

## Risks and Mitigations

- **None** — all six changes are inside `#` comments; zero
  evaluation-affecting lines touched. Verified via identical `.drv` hashes
  before/after in Phase 3.
