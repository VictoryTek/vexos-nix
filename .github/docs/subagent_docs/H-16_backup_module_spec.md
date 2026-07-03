# H-16 — Declarative restic backup module

Status: Phase 1 (Research & Specification)
Source: MASTER_PLAN FEATURES 2.1

## Current State

No backup tooling exists anywhere in this repo. `grep` across `modules/server/*.nix` and
`justfile` for `restic`/`backup` turns up nothing except unrelated comments (Immich's
tagline, `just update`'s flake.lock backup). 50+ optional server services
(`justfile:_server_service_names`) can hold irreplaceable state with no way to recover it
short of the underlying storage itself surviving.

## Problem Definition

Add an opt-in, declarative backup module using the upstream `services.restic.backups`
NixOS module (verified directly against the pinned nixpkgs revision in
`nixos/modules/services/backup/restic.nix` — no new flake input, so no Context7 lookup
required), that automatically backs up the data directories of whichever services are
already enabled, without the user having to maintain a path list by hand.

## Proposed Solution

`modules/server/backup.nix`, new file, imported by `modules/server/default.nix`:

- `vexos.server.backup.enable` (bool, default false).
- `vexos.server.backup.repository` (str) / `repositoryFile` (nullable path) — mirrors
  restic's own repository/repositoryFile split.
- `vexos.server.backup.passwordFile` (path, required via assertion) — restic repo password.
- `vexos.server.backup.extraPaths` (listOf str, default `[]`) — escape hatch for anything
  not covered by the default table below (e.g. Syncthing, which by this repo's own
  `syncthing.nix:48` config stores data at the *entire* user home directory — deliberately
  excluded from the automatic table so backup scope doesn't silently become "the whole
  home directory"; users who want it can add it here explicitly).
- `vexos.server.backup.pruneOpts` (listOf str, default `[ "--keep-daily 7" "--keep-weekly 4" "--keep-monthly 6" ]`).
- `vexos.server.backup.timerConfig` (attrs, default `{ OnCalendar = "daily"; Persistent = true; }`).

Default path assembly:

- A static attrset maps each `_server_service_names` entry to its known data directory.
  The large majority follow the NixOS convention of `/var/lib/<service-name>` (verified
  spot-checks: minio `dataDir` upstream default, attic/dockhand's own configurable
  `dataDir` options read live from `config.vexos.server.<x>.dataDir` rather than
  hardcoded). A handful of documented exceptions:
  - `syncthing` — excluded (see above; whole-home-dir data path).
  - `proxmox` — `/var/lib/pve-cluster` + `/etc/pve` (per the existing comment in
    `proxmox.nix:15`).
  - `attic` / `dockhand` — read from their own `dataDir` options instead of a literal string,
    so the backup module stays correct if those defaults ever change.
- `lib.optionals config.vexos.server.<name>.enable [ path ]` per entry, concatenated —
  only paths for services actually enabled on this host end up in the backup set. This
  directly matches the H-16 wording ("assemble default paths from enabled services").
- PostgreSQL pre-hook: gated on `config.services.postgresql.enable` (system-wide, not
  per-app, since none of this repo's service wrappers currently expose their own
  `database.createLocally`-style option — postgres is either off entirely or configured
  directly by the user outside these wrappers). Uses restic's own
  `backupPrepareCommand` to run `sudo -u postgres pg_dumpall > /var/backup/postgresql-dump.sql`
  into a fixed staging path that's added to `paths` only when postgres is enabled —
  matches the pattern from restic's own module documentation example.

Failure alerts: H-17 (ntfy wiring) doesn't exist yet, so `backup.nix` won't hard-depend on
it. Instead, `systemd.services."restic-backups-main".onFailure` is left as a documented,
empty extension point (a comment showing the one line to add once H-17 lands), rather
than referencing a module that isn't there.

## justfile Extension Points

- Add `backup` to `_server_service_names` so `just enable backup` / `just disable-feature`
  style tooling recognizes it.
- Add a `status` case: `backup) UNITS="restic-backups-main"; URLS="";`.
- Add to the services description table (`_svc backup "Declarative restic backups"`).
- New `just backup-now` recipe: `systemctl start restic-backups-main.service --wait`, for
  manually triggering a backup outside the daily timer.
- `just enable backup` needs a one-time interactive prompt for `repository` and
  `passwordFile` (mirrors the existing Proxmox IP-prompt pattern at
  `justfile:1620-1652`), since both are required and have no sensible default.

## Configuration Changes

None to `flake.nix`. No new flake inputs — `services.restic.backups` is a stock nixpkgs
module, already available via the existing NixOS module set.

## Risks and Mitigations

- **Repository target is user-specific** (local disk, SFTP, B2, etc.) — the module only
  provides the generic `repository`/`repositoryFile`/`passwordFile` options exactly as
  restic itself exposes them; no attempt to pick a default remote.
- **Default path table drift**: as new server modules are added, the table needs a new
  line. Documented with a comment at the top of the table pointing at
  `justfile:_server_service_names` as the canonical service list to stay in sync with.
- **Syncthing/proxmox exceptions**: documented inline, not silently handled.
