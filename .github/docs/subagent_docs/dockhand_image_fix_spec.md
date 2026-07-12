# Dockhand Image Fix — Spec

## Current State Analysis

`modules/server/dockhand.nix` deploys Dockhand as an OCI container via
`virtualisation.oci-containers.containers.dockhand`, pinned to:

```nix
image = "ghcr.io/finsys/dockhand:v1.0.36";
```

On the live host (`vexos-vmc`), `docker-dockhand.service` fails with exit code
125 and hits `start-limit-hit` after 5 restarts. Reproduced locally:

```
$ docker pull ghcr.io/finsys/dockhand:v1.0.36
Error response from daemon: Head "https://ghcr.io/v2/finsys/dockhand/manifests/v1.0.36": denied

$ docker pull ghcr.io/finsys/dockhand:latest
Error response from daemon: Head "https://ghcr.io/v2/finsys/dockhand/manifests/latest": denied
```

`docker create`/`docker run` returns 125 when it cannot even construct the
container (here: image pull failure), which is exactly what the failing
systemd unit shows — the container process itself never starts.

## Problem Definition

`ghcr.io/finsys/dockhand` is not a valid public image reference (denied on
every tag tried, including `:latest`). The upstream project publishes to
Docker Hub as `fnsys/dockhand`, not to GHCR under `finsys/dockhand`.

Verified against the [Dockhand manual](https://dockhand.pro/manual/) and by
direct pull test:

```
$ docker pull fnsys/dockhand:latest
... Status: Downloaded newer image for fnsys/dockhand:latest
```

Confirmed via Docker Hub tags API (`hub.docker.com/v2/repositories/fnsys/dockhand/tags`)
that versioned tags exist, latest being `v1.0.37` (pushed 2026-07-11), matching
this project's convention of pinning to a specific version rather than
`:latest` (see `portainer.nix:57` → `portainer/portainer-ce:2.43.0`,
`arcane.nix:109` → `ghcr.io/getarcaneapp/manager:v1.19.4`).

## Proposed Solution

Change the single `image` line in `modules/server/dockhand.nix` from:

```nix
image = "ghcr.io/finsys/dockhand:v1.0.36";
```

to:

```nix
image = "fnsys/dockhand:v1.0.37";
```

No other logic, options, or module structure changes — this is a one-line
image-reference correction. No new flake inputs, no new modules, no Option B
architecture impact.

## Implementation Steps

1. Edit `modules/server/dockhand.nix` line 87: replace the `image` value.
2. No changes needed elsewhere — `dataDir`, `ports`, `volumes`, `environment`,
   `user`, and the backend/podman assertions are all independent of the image
   registry/tag.

## Dependencies

None (no new flake inputs; this only changes an OCI image tag, which is
resolved at container-runtime, not at Nix evaluation time). Context7 is not
applicable — this is not a library/SDK integration.

## Configuration Changes

`modules/server/dockhand.nix:87` — `image` value only.

## Risks and Mitigations

- **Risk:** `fnsys/dockhand:v1.0.37` could itself change/be pulled at deploy
  time introducing behavior differences from `v1.0.36`.
  **Mitigation:** Pinning to `v1.0.37` (verified to exist and pull
  successfully) rather than `:latest` keeps behavior reproducible; user can
  re-pin later if needed.
- **Risk:** Docker Hub pull-rate limits on anonymous pulls.
  **Mitigation:** Out of scope for this fix — pre-existing behavior shared
  by all other `virtualisation.oci-containers` services in this repo.
- No changes to volumes, ports, assertions, or firewall rules — blast radius
  is limited to which image gets pulled/run.
