# M-07 — Dead `gnome-background-reload` resume service

Status: Phase 1 (Research & Specification)
Source: MASTER_PLAN M-07 · `modules/system-nosleep.nix:69-93`

## Current State

`systemd.services."gnome-background-reload"` is `wantedBy = [ "suspend.target"
"hibernate.target" "hybrid-sleep.target" ]` — but those exact same three targets (plus
`sleep.target`/`suspend-then-hibernate.target`) are permanently masked by this same
file's own "Layer 4" (`systemd.suppressedSystemUnits`, lines 9-15), which symlinks them
to `/dev/null`. A systemd unit masked to `/dev/null` can never transition to an active
state, so nothing can ever pull in a unit that's `WantedBy=` it — this service can
never execute, regardless of any other condition. Combined with Layers 1-3 (dconf power
settings, logind ignore, sleep.conf AllowSuspend=no) also preventing sleep from ever
actually happening at all, this "belt-and-suspenders post-resume workaround" targets an
event (waking from suspend/hibernate) that is now structurally impossible on this
system — not fragile, but literally unreachable.

## Problem Definition

Remove code that can never execute, per this module's own design.

## Proposed Solution

Delete the entire "Belt-and-suspenders: post-resume GNOME background reload" block
(header comment through the closing brace of the service definition).

## Implementation Steps

1. `modules/system-nosleep.nix` — remove the dead block.

## Configuration Changes

None.

## Risks and Mitigations

- **None** — the block is unreachable by construction (masked target units it depends
  on for activation); removing it changes no observable behavior.
