# L-18 — Retired stdout-protocol comment archaeology

Status: Phase 1 (Research & Specification)
Source: MASTER_PLAN L-18 (ARCH 4.5) · `modules/nix.nix:121-127,185-193`
(current location: `pkgs/vexos-update/default.nix:20-21`)

## Current State

`modules/nix.nix` itself is now only 123 lines (the ~230-line
`vexos-update` script was moved to `pkgs/vexos-update/default.nix` during
M-26 this session) — the plan's cited line numbers are stale, and
`modules/nix.nix` has zero "retired"/legacy protocol comments left at all.
The actual dead comments moved along with the script to
`pkgs/vexos-update/default.nix:20-21`:
```
#   Legacy: "VEXOS_CACHE_LOCAL_OK:" was the prior allowed-list prefix (retired).
#   Legacy: "VEXOS_CACHE_MISS:" was the original single-channel prefix (retired).
```

Confirmed both are genuinely dead on both sides of the integration:
- Grepped the actual script body in `pkgs/vexos-update/default.nix` —
  neither prefix is emitted anywhere; only `VEXOS_CACHE_BLOCK:` and
  `VEXOS_LOCAL_BUILD:` are used.
- Checked the Up GUI app's actual current source (`src/`, fetched via its
  flake input) — neither prefix appears there either. (Up's own historical
  `.github/docs/subagent_docs/` spec/review artifacts still mention
  `VEXOS_CACHE_MISS:` from when that feature was originally built, but
  that's a docs artifact in a separate repo, not live code — out of scope
  here.)

## Problem Definition

Two lines of dead documentation-of-documentation: comments describing
prefixes that were retired before either side of the protocol currently
uses them.

## Proposed Solution

Remove the two "Legacy:" lines, matching the plan's own proposal — git
history retains them if ever needed.

## Implementation Steps

1. `pkgs/vexos-update/default.nix` — delete the two "Legacy:" comment
   lines.

## Configuration Changes

None — comment-only change.

## Risks and Mitigations

- **None** — comment-only; verified via identical build output that
  nothing evaluation/build-affecting changed.
