# M-28 — Output/group counts wrong in CLAUDE.md, CI comment, and preflight script

Status: Phase 1 (Research & Specification)
Source: MASTER_PLAN M-28 (ARCH 2.3)

## Current State

The MASTER_PLAN's description of this item is stale (written against an older repo
state) — re-verified every claim directly against current files rather than trusting it:

- **`ci.yml:64-65` "4 groups/22 configs"** — already correct. Current text reads "6
  groups × ~5 min each" / "instead of all 30 configs", and the matrix genuinely defines
  6 groups × 5 configs = 30. No change needed here.
- **`flake.nix:277` vs `flake.nix:351`** — these two comments *disagree with each other*
  in the same file. Line 277 (right above `hostList`) correctly says "30 outputs total:
  25 role/GPU variants + 5 vanilla role variants." Line 351 (right after `hostList`,
  above the `nixosConfigurations` definition) says "34 outputs" — wrong. Counted
  `hostList` directly (`grep -c '{ name = "vexos-'`) — 30 entries, confirming line 277
  is correct and line 351 is the actual bug.
- **`CLAUDE.md:194-196`** — states "The flake defines 30 outputs across six roles... ×
  GPU variants (`amd`, `nvidia`, `nvidia-legacy535`, `nvidia-legacy470`, `intel`, `vm`
  — not all roles include all six variants)". The "30 outputs / six roles" part is
  correct. But `nvidia-legacy470` does not exist anywhere in this repo — not in
  `hostList`, not in `ci.yml`'s matrix, not in `modules/gpu/` (only `amd`, `amd-headless`,
  `intel`, `intel-headless`, `nvidia`, `nvidia-headless`, `vanilla-vm`, `vm` exist — no
  `nvidia-legacy470` variant of any kind). Every role that has nvidia only has
  `nvidia` and `nvidia-legacy535`. So the variant list only has 5 members, not six, and
  one of the six named doesn't exist at all.
- **`preflight.sh:14`** — comment says "(all 5 configuration-*.nix files)". Counted
  directly (`ls configuration-*.nix | wc -l`) — 6 files (`desktop`, `headless-server`,
  `htpc`, `server`, `stateless`, `vanilla`). Stale by one.
- **`CLAUDE.md:152`** — "`bash scripts/preflight.sh` — full pre-push validation (all 7
  checks)". Counted actual stages (`grep '^echo "\['`) — 9 stages, `[0/8]` through
  `[8/8]` (M-26 added stage 8 without updating this line). Stale.
- **`flake.nix` `# NEW` markers`** — grepped for `NEW` in `flake.nix`; none found. Already
  removed at some point prior to this session. No action needed.

## Problem Definition

Four numbers have drifted out of sync with the code they describe:
1. `flake.nix:351` comment says 34 outputs; actual/correct is 30 (and contradicts
   `flake.nix:277` two comments above it).
2. `CLAUDE.md:196` lists a GPU variant (`nvidia-legacy470`) that doesn't exist, and
   says "six variants" when only 5 exist.
3. `preflight.sh:14` says 5 `configuration-*.nix` files; actual is 6.
4. `CLAUDE.md:152` says preflight has 7 checks; actual is 9 stages (`[0/8]`-`[8/8]`).

`ci.yml`'s group/config counts and `flake.nix`'s `# NEW` markers are already correct —
no change needed for those two sub-items despite the MASTER_PLAN describing them as
broken.

## Proposed Solution

Direct text fixes only, no logic changes:
1. `flake.nix:351` — "34 outputs" → "30 outputs".
2. `CLAUDE.md:196` — remove `nvidia-legacy470` from the variant list, change "six
   variants" → "five variants".
3. `preflight.sh:14` — "(all 5 configuration-*.nix files)" → "(all 6
   configuration-*.nix files)".
4. `CLAUDE.md:152` — "(all 7 checks)" → "(9 stages, `[0/8]`-`[8/8]`)".

## Implementation Steps

1. Edit `flake.nix:351`.
2. Edit `CLAUDE.md:196` (variant list) and `CLAUDE.md:152` (check count).
3. Edit `preflight.sh:14`.

## Configuration Changes

None — comments/docs only, no option or build-logic changes.

## Risks and Mitigations

- **None** — purely comment/doc text; no `.nix` evaluation-affecting line is touched
  (line 351 and preflight.sh:14 are both inside `#` comments).
