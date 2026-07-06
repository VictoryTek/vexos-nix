# L-17 — Expired `TODO(2026-05)` in `plex.nix`

Status: Phase 1 (Research & Specification)
Source: MASTER_PLAN L-17 (ARCH 4.4) · `modules/server/plex.nix:43`

## Current State

`modules/server/plex.nix`'s workaround (forcing
`systemd.services.plex.environment.LD_LIBRARY_PATH = ""` when Plex Pass
hardware transcoding is off) carries `TODO(2026-05)` — already past
today's date (2026-07-06), confirming the plan's "expired" framing.

Re-verified whether the underlying upstream bug is actually fixed, per the
TODO's own prescribed check — but ran it correctly: the TODO's suggested
`nix eval` command checks the *final* `LD_LIBRARY_PATH` value, which is
useless as a test on its own since our module's `mkForce ""` is what
produces that empty result regardless of upstream behavior. Instead,
inspected the pinned nixpkgs' actual `services.plex` module source
directly: `nixos/modules/services/misc/plex.nix` still sets
```
environment.LD_LIBRARY_PATH = "/run/opengl-driver/lib";
```
**unconditionally** (no `lib.mkIf`, no gating on hardware-acceleration
settings) — the exact behavior this workaround exists to counteract. The
workaround is still needed.

**Also found the tracking link itself is broken**: `Track:
https://github.com/NixOS/nixpkgs/issues/310792` points at an unrelated,
already-closed issue ("goose: 3.19.2 -> 3.20.0", closed 2024) — not
about Plex at all. Searched GitHub for the actual bug
(`__isoc23_sscanf` / libva / glibc symbol mismatch) and found issue
**#468070** ("plex: fails after installing libva") describing the
identical crash signature and root cause, but it was closed as a
user-configuration issue (manually adding `libva` to
`hardware.graphics.extraPackages` alongside a mismatched OS/package
version), not as a fix to the module's unconditional
`LD_LIBRARY_PATH` injection — so it isn't a clean replacement link
either; citing it without qualification would be almost as misleading
as the broken one.

## Problem Definition

The workaround is still required (confirmed via direct source
inspection), the TODO date has passed, and its tracking link points at
the wrong issue entirely.

## Proposed Solution

Replace the broken issue link with a stable, self-verifying pointer at
the exact upstream module file/line to check (immune to issue
renumbering/closure, unlike a GitHub link), correct the verification
command's framing (note that it only reflects our own workaround, not
upstream state), and re-date the TODO to the next natural checkpoint —
this repo's next stable NixOS release cycle (26.11, following the
current 26.05 pin).

## Implementation Steps

1. `modules/server/plex.nix` — update the TODO block: new date
   (`2026-11`), replace the broken issue link with a pointer to the
   specific upstream module file to check, and clarify the verification
   note.

## Configuration Changes

None — comment-only change; the workaround itself (`lib.mkForce ""`)
remains unchanged since it's still needed.

## Risks and Mitigations

- **None** — comment-only change; verified via identical `.drv` hash that
  nothing evaluation-affecting changed.
