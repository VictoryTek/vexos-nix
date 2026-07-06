# L-16 — Empty `overlays/` directory listed as a key directory in CLAUDE.md

Status: Phase 1 (Research & Specification)
Source: MASTER_PLAN L-16 (ARCH 4.3)

## Current State

`overlays/` exists on disk as an empty directory. Confirmed it is **not
tracked by git at all** (`git ls-files overlays/` and
`git status overlays/ --short` both return nothing) — git has no concept of
empty directories, so this is purely a local filesystem leftover, not part
of the repository's tracked content. `CLAUDE.md:182` still lists
`overlays/` — nixpkgs overlays" under "Key Directories", but as
`modules/branding.nix`'s own header and `flake.nix` confirm, overlays
actually live inline in `flake.nix` (`unstableOverlayModule`,
`customPkgsOverlayModule`) and `pkgs/default.nix` — matching the plan's own
description.

## Problem Definition

CLAUDE.md documents a directory that doesn't contain anything and isn't
part of the tracked repo, misleading a reader into thinking overlays are
organized as standalone files there.

## Proposed Solution

Remove the empty, untracked local directory and delete the stale
"Key Directories" line from CLAUDE.md.

## Implementation Steps

1. Remove the local `overlays/` directory (empty, untracked — no git
   operation needed since it was never tracked).
2. `CLAUDE.md` — delete the `overlays/` bullet from "Key Directories".

## Configuration Changes

None.

## Risks and Mitigations

- **None** — the directory is empty and untracked; removing it has no
  effect on any tracked file or build output.
