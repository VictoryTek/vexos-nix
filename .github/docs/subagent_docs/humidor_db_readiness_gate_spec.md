# Humidor DB readiness gate — Spec

## Current state analysis

- `modules/server/humidor.nix` deploys Humidor as a two-container OCI stack
  (`humidor` app + `humidor-db` postgres:17), following the same pattern as
  `modules/server/joplin.nix` and `modules/server/home-registry.nix`.
- `virtualisation.oci-containers.containers.humidor.dependsOn = [ "humidor-db" ]`
  adds `After=docker-humidor-db.service` / `Requires=docker-humidor-db.service`
  to `docker-humidor.service` (nixpkgs `oci-containers.nix`, `mkService`).
- For the `docker` backend (unlike `podman`), the generated unit is
  `Type=simple` with `ExecStart = exec docker run ...` (no `-d`, no
  `sd_notify`). systemd marks the unit "active (running)" the instant the
  `docker run` process forks — before the image is even pulled, let alone
  before the postgres entrypoint finishes `initdb` and starts listening.
  `dependsOn` therefore only guarantees `docker-humidor-db.service` was
  *started*, not that Postgres inside it is *ready to accept connections*.
- Confirmed live on a test server VM (`journalctl`, 2026-09-26): on first
  activation, `docker-humidor.service` started immediately after
  `docker-humidor-db.service`, while `humidor-db`'s image was still pulling.
  The Humidor (Rust) binary attempted its DB connection immediately on boot
  and does not retry internally — it exits 1 on the first failed connect.
  Two failures were observed in sequence:
  1. `failed to lookup address information: Try again` — `humidor-db`
     container/network alias didn't exist yet.
  2. `Connection refused` — container existed, Postgres was still running
     `initdb`.
  systemd's default `Restart=on-failure` (set by the oci-containers module)
  retried the container twice; the third attempt succeeded once Postgres was
  actually accepting connections (~50s after first activation). The service
  is not currently failed (`systemctl --failed` is empty) and has been
  serving `/health` checks successfully since.
- `modules/server/joplin.nix` does not exhibit this because the
  `joplin/server` image's Node/Knex DB client retries the connection
  internally; Humidor's Rust binary does not.
- `modules/server/home-registry.nix` is structurally identical to
  `humidor.nix` (same `dependsOn`-only gating, same non-retrying Rust app
  pattern) and is very likely subject to the same race, but it has not been
  reported as an issue and is out of scope for this fix — noted for the user
  separately, not changed here.

## Problem definition

`docker-humidor.service` can start before `humidor-db`'s Postgres is
actually accepting connections. The app doesn't retry, so it crashes and
relies on systemd's automatic restarts to eventually catch up. This is
self-healing today (~2 restarts, ~35-50s) but is a real race that will
recur on every cold start of the stack (fresh VM, host reboot), producing
`FAILURE` cycles in the journal that look like a broken deployment.

## Proposed solution

Extend the existing `humidor-app-env-init` oneshot unit (already a hard
`Requires`/`After` dependency of `docker-humidor.service`) to:

1. Additionally order itself `After=`/`Requires=docker-humidor-db.service`,
   so it doesn't attempt to poll a container that was never created.
2. After composing `appEnvFile` as it does today, poll
   `docker exec humidor-db pg_isready` in a loop (1s interval, 60s timeout)
   before exiting successfully. `pg_isready` only checks that the server is
   accepting connections — it doesn't require valid credentials or a
   matching database, so no additional env/auth wiring is needed.
3. On timeout, exit 1 with a clear message, so a genuinely stuck Postgres
   surfaces as an activation failure instead of an infinite silent loop.

This keeps `docker-humidor.service` blocked (via its existing `Requires` on
`humidor-app-env-init.service`) until Postgres is verifiably ready, instead
of just "started". No new units, no new config options — the wait folds
into the unit that's already a hard prerequisite of the app container.

### Why not gate on `docker-humidor-db.service` directly with a healthcheck?

nixpkgs' `oci-containers` module has no built-in "wait for healthy" concept
for the `docker` backend (that's a `podman`-only `sdnotify` feature). Adding
a Docker `HEALTHCHECK`/`--health-cmd` to the `humidor-db` container wouldn't
by itself block `docker-humidor.service` either, since ordering is unit
based, not container-health based. A poll loop in a oneshot unit that's
already a hard dependency is the minimal mechanism available.

## Implementation steps

- `modules/server/humidor.nix`: modify `systemd.services."humidor-app-env-init"`
  — add `docker-humidor-db.service` to `after`/`requires` (unconditionally),
  and append the `pg_isready` wait loop to `script` after the existing
  `DATABASE_URL` composition.
- No changes to options, container definitions, firewall rules, or the
  backup/dump-timer configuration.
- Update the module's stopgap comment block only if the added ordering
  needs explanation (comment is being added inline with the change).

## Dependencies

None — `pg_isready` ships inside the `postgres:17` image already in use
(invoked via `docker exec`), and `${pkgs.docker}` is already used elsewhere
in this file. No new nixpkgs inputs or Context7 lookups required (internal
systemd/docker change only, no new library).

## Configuration changes

None (no new `vexos.server.humidor.*` options).

## Risks and mitigations

- **Risk:** poll loop hides a real Postgres startup failure behind a 60s
  wait before failing.
  **Mitigation:** the loop exits 1 with a clear stderr message on timeout,
  which fails the unit and cascades to `docker-humidor.service` not
  starting — same CRITICAL-visibility as today's crash loop, but without
  the app container flapping.
- **Risk:** `docker exec humidor-db pg_isready` runs as root via systemd;
  no new privilege surface since `humidor-app-env-init` already runs as
  root and `${pkgs.docker}` is already a dependency of this module.
- **Risk:** existing running deployments (already-healthy `humidor-db`)
  re-run `humidor-app-env-init` on every activation (`wantedBy =
  multi-user.target`, no `ConditionPathExists` guard) — the new wait loop
  adds at most one `pg_isready` round-trip (sub-second) when Postgres is
  already up, no behavior change for the steady-state case.
