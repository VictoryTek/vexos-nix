# M-32 — Add qBittorrent + Bazarr opt-in options to the arr stack

Status: Phase 1 (Research & Specification)
Source: MASTER_PLAN M-32 (FEATURES 2.4) · `modules/server/arr.nix`

## Current State

`modules/server/arr.nix` bundles SABnzbd (port 8080), Sonarr (8989), Radarr
(7878), Lidarr (8686), and Prowlarr (9696) under a single
`vexos.server.arr.enable` flag — one file for the whole stack (a pre-existing
deviation from this repo's usual one-file-per-service convention; out of
scope to change here, and the MASTER_PLAN's exact requested option paths
(`vexos.server.arr.qbittorrent.enable`, `vexos.server.arr.bazarr.enable`)
confirm the intent is to nest these as sub-toggles of the existing module,
not spin off two new top-level modules).

Checked both NixOS modules directly (`nixos/modules/services/torrent/qbittorrent.nix`,
`nixos/modules/services/misc/bazarr.nix`):
- `services.qbittorrent` — `openFirewall` (bool, default false, opens both
  `webuiPort` and `torrentingPort`), `webuiPort` (default **8080** — collides
  with this repo's SABnzbd default), `torrentingPort` (default `null` — no
  port passed to `--torrenting-port`, meaning qBittorrent picks a random port
  each run, which can't be usefully firewalled).
- `services.bazarr` — `openFirewall` (bool, default false), `listenPort`
  (default 6767, no conflict with any port already used in `arr.nix`).

## Problem Definition

Need to add qBittorrent and Bazarr as individually toggle-able additions to
the arr stack, without colliding with SABnzbd's existing port 8080 and
without leaving qBittorrent's torrenting port unfirewalled/unset.

## Proposed Solution

Add two nested enable options to `modules/server/arr.nix`:
`vexos.server.arr.qbittorrent.enable` and `vexos.server.arr.bazarr.enable`,
both requiring the parent `vexos.server.arr.enable = true` (enforced via an
unconditional assertion, not just implicit no-op nesting, matching the
existing cross-service assertion style used in `dockhand.nix`).

- qBittorrent: `webuiPort = 8081` (shifted off SABnzbd's 8080, matching this
  repo's existing port-shift convention — see `dockhand.nix`'s comment on
  its own port shift), `torrentingPort = 6881` (the IANA-registered
  conventional BitTorrent port, so it's a real, fixed, firewallable value
  instead of `null`), `openFirewall = true`.
- Bazarr: `openFirewall = true`, default `listenPort` (6767) kept as-is — no
  conflict.
- Add `qbittorrent`/`bazarr` to the primary user's `extraGroups` only when
  each is enabled, matching the existing pattern for the other four
  services.

## Implementation Steps

1. `modules/server/arr.nix` — add `qbittorrent.enable` / `bazarr.enable`
   options, wire `services.qbittorrent` / `services.bazarr`, extend
   `extraGroups`, add the two prerequisite assertions.

## Configuration Changes

None — both new options default to `false`; no behavior change for any host
that doesn't explicitly enable them.

## Risks and Mitigations

- **Risk:** qBittorrent's `webuiPort` default (8080) collides with SABnzbd's.
  **Mitigation:** explicitly set `webuiPort = 8081`.
- **Risk:** qBittorrent's `torrentingPort` defaults to `null`, so
  `openFirewall = true` would open nothing for the actual torrent-transfer
  port.
  **Mitigation:** set a fixed `torrentingPort = 6881`.
- **Risk:** enabling a sub-toggle without the parent stack enabled would
  silently no-op (since the sub-option only takes effect inside the
  `lib.mkIf cfg.enable` block).
  **Mitigation:** added unconditional assertions (outside the `mkIf`) that
  fail evaluation with a clear message if `qbittorrent.enable`/`bazarr.enable`
  is set without `arr.enable`.
