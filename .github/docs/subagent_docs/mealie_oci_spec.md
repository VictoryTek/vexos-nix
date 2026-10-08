# Mealie → OCI container — Specification

## Current state
`modules/server/mealie.nix` uses `services.mealie` (nixpkgs `pkgs.mealie`):
stable 26.05 = 3.16.0, locked unstable = 3.22.0, upstream latest = v3.28.0
(published 2026-09-24). Mealie refuses to restore backups from a newer
version, so a 3.28.0 backup cannot be restored.

## Solution
Replace the native service with an OCI container pinned to
`ghcr.io/mealie-recipes/mealie:v3.28.0` (upstream-recommended: explicit tag,
SQLite, container port 9000, data at `/app/data`, memory limit, TZ).
Follows the `uptime-kuma.nix` pattern (named volume, docker backend default,
backup path resolved per backend). Options `enable`/`port`/`openFirewall`
unchanged; proxy.nix and template need no change.

## Implementation
- `virtualisation.oci-containers.containers.mealie`: image, `ports = port:9000`,
  `volumes = mealie-data:/app/data`, env `TZ = config.time.timeZone` (fallback UTC),
  `ALLOW_SIGNUP=false`, `--memory=1000m` via extraOptions.
- Backup path: named-volume `_data` dir, backend-dependent (as uptime-kuma).
- Drop `services.mealie`.

## Sources
Mealie docs (SQLite install guide, mealie-next), GitHub releases API,
nixpkgs package.nix (unstable), repo modules uptime-kuma.nix / joplin.nix.

## Risks
- Native service state (/var/lib/private/mealie) not migrated — restore from backup instead.
- Image digest not pinned (consistent with other modules).
- ALLOW_SIGNUP=false is upstream-doc default for the example; restore of backup brings its own users.
