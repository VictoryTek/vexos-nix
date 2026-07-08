# Joplin Server — Postgres "Permission Denied" Fix — Spec

## Current State Analysis

`modules/server/joplin.nix` runs a dedicated `postgres:16` OCI container
(`joplin-db`) with its data directory bind-mounted from the host:

```nix
volumes = [ "${cfg.dataDir}/postgres:/var/lib/postgresql/data" ];
```

The module also declares tmpfiles rules (`modules/server/joplin.nix:144-148`):

```nix
systemd.tmpfiles.rules = [
  "d ${cfg.dataDir} 0700 root root -"
  "d ${cfg.dataDir}/postgres 0700 root root -"
  "d ${cfg.dataDir}/dump 0700 root root -"
];
```

## Problem Definition

The official `postgres` Docker image manages ownership of its own data
directory internally: on first run its root-owned entrypoint initializes
`PGDATA` and chowns it to the in-image `postgres` user (UID 999), then drops
privileges via `gosu` before starting the server. The host directory does not
need — and must not have — its ownership independently enforced.

`systemd-tmpfiles` `"d"` type lines re-assert the configured owner/mode on
**every** `systemd-tmpfiles --create` run, not only on first creation. NixOS
runs `systemd-tmpfiles --create` as part of every `nixos-rebuild switch`
activation. So every activation — regardless of whether that activation
touches `joplin.nix` at all — resets `${dataDir}/postgres` back to
`root:root 0700`, stripping access from the already-running Postgres
container's UID-999 process without restarting it. The next time that live
backend opens a data file (e.g. `global/pg_filenode.map`), it gets
`Permission denied`. This matches the reported sync failure exactly, and
explains why an update unrelated to Joplin (`45203b6` image bump,
`f6a3790` flake input bump — both on 2026-07-08) broke it: any activation
reasserts the rule.

## Proposed Solution

Drop host-level ownership enforcement for the `postgres/` data subdirectory;
let the container own it as designed. Keep tmpfiles management for the
directories NixOS/host processes actually write to directly
(`dataDir` itself, and `dataDir/dump`, which is written by the host-side
`pg_dump` redirect in the nightly backup unit — that unit runs as root, so
`root:root 0700` there is correct and unaffected by this bug).

```nix
systemd.tmpfiles.rules = [
  "d ${cfg.dataDir} 0700 root root -"
  "d ${cfg.dataDir}/dump 0700 root root -"
];
```

Docker auto-creates a missing bind-mount source directory (owned by root,
default mode) before handing it to the container, so removing the explicit
rule for `postgres/` does not affect first-boot provisioning — the
postgres image's own root entrypoint still performs `initdb` + `chown` on an
empty/missing-permission directory exactly as it does today.

## Implementation Steps (Module Architecture Pattern — Option B)

This is a same-file, same-role fix — no new module split needed:
`modules/server/joplin.nix` is already a role-specific addition file
(imported only by the server role configuration that enables
`vexos.server.joplin`). No `lib.mkIf` guards by role/display/gaming flag are
being added or removed.

1. Remove the `"d ${cfg.dataDir}/postgres 0700 root root -"` line from
   `systemd.tmpfiles.rules` in `modules/server/joplin.nix`.
2. Add a one-line comment on the remaining rules explaining why the
   `postgres/` subdirectory is deliberately excluded (non-obvious constraint
   — a future reader would otherwise "helpfully" re-add it).

## Dependencies

None — no new packages, containers, or flake inputs. Context7 lookup not
required per policy (internal code change, no new external library).

## Configuration Changes

None user-facing. `vexos.server.joplin.enable = true;` behavior is unchanged
for new deployments; existing deployments are unaffected going forward.

## Immediate Remediation for the Already-Broken Host

The code fix prevents *future* recurrence but does not retroactively repair
ownership that was already reset to `root:root` on the live host. The
Postgres container must be restarted so its root entrypoint re-chowns
`PGDATA` before dropping privileges again:

```
sudo systemctl restart docker-joplin-db.service
```

This is a live-system action and must be run by the user — it is not
something this workflow executes. It does not require a full
`nixos-rebuild switch`; restarting the one systemd unit is sufficient and
lower-blast-radius.

## Risks and Mitigations

- **Risk:** Removing the tmpfiles rule means the directory won't pre-exist
  with restrictive permissions before first container start.
  **Mitigation:** Docker creates missing bind-mount sources itself, and the
  postgres image's entrypoint chowns/initializes on first run regardless —
  this is the documented, standard behavior for this image and matches how
  every other bind-mounted container in this repo already behaves (none of
  them pre-create their data subdirectory via tmpfiles either).
- **Risk:** Someone re-adds the removed rule later without knowing why.
  **Mitigation:** Explanatory comment left in place per repo comment
  conventions (WHY, not WHAT).
