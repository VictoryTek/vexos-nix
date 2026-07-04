# M-22 — Seven OCI containers track `:latest`

Status: Phase 1 (Research & Specification)
Source: MASTER_PLAN M-22 (BUGS M25, ARCH 3.2) · `portainer.nix`, `homepage.nix`,
`stirling-pdf.nix`, `authelia.nix`, `nginx-proxy-manager.nix`, `dockhand.nix`,
`dozzle.nix` (all read in full)

## Current State

All seven modules pin `image = "...:latest"`, confirmed by grep. Each container
silently self-updates on next pull with no way to reproduce a prior deployment, and
`:latest` for `homepage` was already the direct cause of M-17's
`HOMEPAGE_ALLOWED_HOSTS` breakage (an upstream behavior change landing unannounced).

## Problem Definition

Pin each image to a specific, verified-current stable release tag instead of
`:latest`, per the MASTER_PLAN's fix.

## Proposed Solution

Verified the actual current stable tag for each image directly (Docker Hub's public
tags API for the five Docker Hub-hosted images, GitHub releases + the live GHCR
package page for the two GHCR-hosted images) rather than guessing a plausible-looking
version string:

| Module | Image | Verified tag | Source |
|---|---|---|---|
| `portainer.nix` | `portainer/portainer-ce` | `2.43.0` | Docker Hub tags API |
| `homepage.nix` | `ghcr.io/gethomepage/homepage` | `v1.13.2` | live GHCR package page (`github.com/gethomepage/homepage/pkgs/container/homepage`) |
| `stirling-pdf.nix` | `frooodle/s-pdf` | `2.14.0` | Docker Hub tags API |
| `authelia.nix` | `authelia/authelia` | `4.39.20` | Docker Hub tags API |
| `nginx-proxy-manager.nix` | `jc21/nginx-proxy-manager` | `2.15.1` | Docker Hub tags API |
| `dockhand.nix` | `ghcr.io/finsys/dockhand` | `v1.0.36` | GitHub releases (`Finsys/dockhand`); image reference itself confirmed legitimate via `dockhand.pro/manual`'s own documented Prometheus example, which explicitly references this exact GHCR path as an official mirror |
| `dozzle.nix` | `amir20/dozzle` | `v10.6.7` | Docker Hub tags API |

`dockhand.nix`'s image reference was checked directly with the user before proceeding
— an initial finding that the Finsys org's GitHub Packages listing didn't show a
`dockhand` package raised a real concern that the reference itself might be wrong, not
just untagged. Confirmed via the project's own hosted manual that `ghcr.io/finsys/dockhand`
is a legitimate, documented alternate registry for the same releases as
`fnsys/dockhand` on Docker Hub — multi-registry mirrors are tagged identically, so the
same `v1.0.36` verified from GitHub releases applies.

## Implementation Steps

1. Update each of the 7 files' `image = "...:latest";` to the pinned tag above.

## Configuration Changes

None.

## Scope Addition: automated weekly pin updates

The user raised a legitimate concern: pinning trades reproducibility for manual
version-bump burden. Resolved by adding `.github/workflows/update-container-images.yml`,
a new scheduled workflow (Wednesdays, matching the existing
`update-flake-lock.yml`'s direct-commit-to-main convention rather than opening PRs —
consistent with this repo's established low-ceremony automation style) that:

- Queries each of the 7 images' registry (Docker Hub's public tags API for the 5
  Docker Hub images; the anonymous GHCR token + `tags/list` flow for the 2 GHCR
  images) for the latest matching version tag.
- Compares against what's currently pinned in each `modules/server/*.nix` file.
- Rewrites only the files whose pinned version is out of date, then commits and
  pushes — mirroring `update-flake-lock.yml`'s "skip commit if nothing changed"
  pattern exactly.

This keeps the flake reproducible between scheduled runs (never mutates the running
image mid-week the way `:latest` did) while still surfacing new versions on a
predictable weekly cadence without requiring manual `just update-containers` runs
(a separate, still-valid MASTER_PLAN item, M-35, for on-demand bumps).

## Risks and Mitigations

- **Tags will go stale between Wednesdays** — acceptable; this is a deliberate,
  predictable cadence rather than continuous `:latest` mutation.
- **Wrong image reference risk for dockhand** — explicitly investigated rather than
  assumed; confirmed legitimate before pinning a version to it.
- **GHCR anonymous token flow reliability** — this sandbox's own network restrictions
  prevented a live end-to-end test of the GHCR lookup path (the standard anonymous
  bearer-token flow); GitHub Actions runners have unrestricted internet access, so this
  should work there, but it's flagged as unverified-in-this-session rather than
  claimed as tested.
- **Version-tag regex per image**: dozzle/homepage/dockhand use a `v` prefix,
  portainer/stirling-pdf/authelia/nginx-proxy-manager don't — the workflow's per-service
  table carries the correct pattern for each rather than a single shared assumption.
