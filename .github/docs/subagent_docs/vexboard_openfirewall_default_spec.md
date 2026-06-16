---
name: vexboard-openfirewall-default
feature: vexboard_openfirewall_default
phase: 1-spec
---

# Spec: Change vexboard openFirewall default to true

## Current State

`modules/server/vexboard.nix` exposes `vexos.server.vexboard.openFirewall` with `default = false`.
The upstream `services.vexboard` module also defaults to `false`. Neither the `just enable`
tooling nor any auto-generated server-services.nix sets this option explicitly.

Result: VexBoard binds to `0.0.0.0:7280` (all interfaces) but the NixOS firewall blocks
port 7280, making the dashboard unreachable from any other machine on the LAN.

## Problem

VexBoard is the default server dashboard — its entire purpose is to be accessed over the
network. Every other LAN-facing service module in this project defaults to `openFirewall = true`
(seerr, jellyfin, audiobookshelf, home-assistant, scrutiny, immich, tautulli, arr stack, etc.).
VexBoard's closed default is an anomaly that silently breaks the intended user experience with
no error message.

## Proposed Solution

Change `default = false` → `default = true` in the `openFirewall` option of
`modules/server/vexboard.nix`. Update the description to reflect the new default.

No other files require changes:
- `template/server-services.nix` has a comment-only reference; no explicit value to update.
- The upstream module is unchanged; the override flows through `services.vexboard.openFirewall = cfg.openFirewall`.

## Implementation Steps

1. In `modules/server/vexboard.nix`, change `openFirewall.default` from `false` to `true`.
2. Update the option description to reflect open-by-default behaviour.

Verify: `nix flake show --impure` + dry-build for server, headless-server, and desktop-amd targets.

## Dependencies

None. Internal change only — no new dependencies, no Context7 required.

## Risks

Low. Opens port 7280 on any server installation where VexBoard is enabled.
VexBoard requires authentication (`VEXBOARD_AUTH__SECRET`) before the preStart guard passes,
so enabling the port does not expose an unauthenticated endpoint.
Users who explicitly needed the port closed can still set `openFirewall = false` in their config.
