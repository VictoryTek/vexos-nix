# Home Registry DB readiness gate — Spec

## Current state analysis

Identical structure and root cause to the fix already applied in
`modules/server/humidor.nix` (see
`.github/docs/subagent_docs/humidor_db_readiness_gate_spec.md` for the full
mechanism writeup — summarized here, not re-derived):

- `modules/server/home-registry.nix` deploys a two-container OCI stack
  (`home-registry` app + `home-registry-db` postgres:17) with
  `virtualisation.oci-containers.containers.home-registry.dependsOn =
  [ "home-registry-db" ]`.
- For the `docker` backend, `docker-home-registry-db.service` reports
  "active" the instant `docker run` forks (`Type=simple`, no `sd_notify`) —
  before the image is pulled or Postgres finishes `initdb`/starts
  listening. `dependsOn` only orders `docker-home-registry.service` after
  that unit *starts*, not after Postgres is *ready*.
- The Home Registry Rust binary does not retry a failed DB connection
  internally (same as Humidor), so it crashes and relies on systemd's
  `Restart=on-failure` to eventually catch up — same crash/restart-loop
  risk on every cold start (fresh VM, host reboot).
- `home-registry-app-env-init` already exists, already composes
  `appEnvFile`, and is already a hard `Requires`/`After` dependency of
  `docker-home-registry.service` — the same lever used for the Humidor fix.

## Problem definition

Same as Humidor: `docker-home-registry.service` can start before
`home-registry-db`'s Postgres is accepting connections, causing an
avoidable crash/restart loop on cold start.

## Proposed solution

Same mechanism as the Humidor fix, applied to
`modules/server/home-registry.nix`:

1. Add `docker-home-registry-db.service` to `home-registry-app-env-init`'s
   `after`/`requires` (unconditionally, alongside the existing conditional
   `home-registry-secrets-init.service` entry).
2. After composing `appEnvFile` (existing logic, including the
   `@`/`:`/`/` password-character rejection for this image's unencoded
   `DATABASE_URL` parser — unchanged), poll
   `docker exec home-registry-db pg_isready` (1s interval, 60s timeout)
   before exiting; exit 1 with a clear message on timeout.

No new units, no new options, no changes to the password-character guard
or to `dumpTimer`/backup config.

## Implementation steps

- `modules/server/home-registry.nix`: modify
  `systemd.services."home-registry-app-env-init"` only — add
  `docker-home-registry-db.service` to `after`/`requires`, append the
  `pg_isready` wait loop to `script`.

## Dependencies

None (same as Humidor fix — `pg_isready` ships in the `postgres:17` image
already used; `${pkgs.docker}` already imported in this file).

## Configuration changes

None.

## Risks and mitigations

Same as the Humidor fix: timeout surfaces as an activation failure (not a
silent hang); no new privilege surface; steady-state re-runs on every
activation add at most one sub-second `pg_isready` round-trip.
