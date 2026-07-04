# M-03 — Unbound port 5353 collides with Avahi mDNS

Status: Phase 1 (Research & Specification)
Source: MASTER_PLAN M-03 · `modules/server/unbound.nix:19`

## Current State

`modules/server/unbound.nix` binds Unbound to UDP+TCP port 5353, with a comment saying
this was chosen "to avoid conflict with AdGuard Home (port 53)". Port 5353 is IANA's
well-known mDNS port, and `modules/network.nix:134-137` (a universal base module,
imported by every role) enables Avahi unconditionally with `openFirewall = true`
("opens UDP 5353 (mDNS)"). Both services would bind UDP 5353 — a genuine, unconditional
collision on every role, not an edge case.

Other references to the current port found via repo-wide grep, all needing the same
update: `template/server-services.nix:106` (comment), `justfile:1429` (status printf),
`justfile:2276` (service-info echo block).

## Problem Definition

Unbound needs a port that doesn't collide with anything else already running by
default. 5353 (mDNS) was already taken by Avahi.

## Proposed Solution

Move Unbound to port 5335 — the conventional "Unbound behind AdGuard/Pi-hole" port used
widely in the self-hosted DNS community for exactly this pattern (AdGuard/Pi-hole on 53,
Unbound as the upstream recursive resolver on 5335). Update all four references found
above to stay consistent.

## Implementation Steps

1. `modules/server/unbound.nix` — port comment, `settings.server.port`, both
   `networking.firewall.allowed{TCP,UDP}Ports` entries: 5353 → 5335.
2. `template/server-services.nix` — comment: "Port 5353" → "Port 5335".
3. `justfile` — the `unbound)` case in the `status` recipe (`:5353` → `:5335`) and the
   `unbound)` case in the service-info block ("Port 5353" → "Port 5335").

## Configuration Changes

None — no options added/removed, no flake changes.

## Risks and Mitigations

- **Nothing else in the repo references Unbound's port as an upstream target** —
  confirmed via grep that `adguard.nix` has no hardcoded reference to Unbound or port
  5353/5335; they're independent modules today, so no chained config to update.
- **Existing deployments with `vexos.server.unbound.enable = true` already running on
  5353** will silently switch to 5335 on next rebuild — acceptable since 5353 was never
  actually usable (Avahi already had it), so nothing that currently works depends on
  5353 continuing to be the port.
