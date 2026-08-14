# Plex Backup/Restore Recipes — Spec

## Current State Analysis
- `modules/server/plex.nix` enables `services.plex`, which uses the standard
  NixOS StateDirectory convention. `modules/server/backup.nix` (the
  restic-based declarative backup system) confirms Plex's data directory is
  `/var/lib/plex` — this is authoritative, already relied on elsewhere in
  the repo.
- `services.plex` runs as a dedicated `plex` user/group (repo already adds
  the primary user to the `plex` group in `plex.nix`, implying the service
  itself runs under a `plex` system user).
- There is no existing standalone single-service tar backup/restore recipe.
  The only existing backup mechanism is `modules/server/backup.nix` +
  `just backup-now`, which is a declarative, ongoing restic backup of *all*
  enabled services to a configured repository — a different tool for a
  different job (continuous retention vs. one-shot migration).
- `justfile` convention for server-only recipes: depend on the private
  `_require-server-role` recipe, which checks `/etc/nixos/vexos-variant`.
- `backup-now` (justfile ~line 1216) is the closest analog: ungrouped,
  depends on `_require-server-role`, uses `#!/usr/bin/env bash` + `set -euo
  pipefail`, checks the target systemd unit exists before acting.
- Destructive operations elsewhere in the justfile (`create-mergerfs-pool`)
  are documented as requiring a typed-keyword confirmation before proceeding.

## Problem Definition
User wants to migrate a Plex install to a new server: a `just backup-plex`
recipe that snapshots `/var/lib/plex` to a single portable tar file, and a
`just restore-plex <tarball>` recipe that, run on the new server (after Plex
is enabled/rebuilt there), restores that data so Plex comes back up with the
same libraries/watch history/settings.

## Proposed Solution

### `just backup-plex [dest]`
- Server-role guarded (`_require-server-role`).
- Errors clearly if `plex.service` unit doesn't exist (Plex not enabled).
- `dest` defaults to `./plex-backup-<YYYYmmdd-HHMMSS>.tar.gz` in the current
  directory if not given.
- Stops `plex.service` before archiving (Plex's SQLite databases are not
  guaranteed consistent/lock-free while the server is running — same caution
  `backup.nix` already takes with `pg_dumpall` for live Postgres data), tars
  `/var/lib/plex` with `tar czf`, restarts `plex.service` in a `trap` so it
  always comes back up even if the tar step fails.
- Prints the resulting file path and size on success.

### `just restore-plex tarball`
- Server-role guarded.
- Errors if the given tarball path doesn't exist, or if `plex.service`
  unit doesn't exist (must `just enable plex && just rebuild` on the new
  server first, same precondition the walkthrough already establishes for
  Attic-style setup flows in this repo).
- Requires a typed `yes` confirmation before proceeding, since this
  overwrites `/var/lib/plex` — matches the repo's existing convention for
  destructive storage operations.
- Stops `plex.service`, moves any existing `/var/lib/plex` to
  `/var/lib/plex.bak-<timestamp>` (not deleted — reversible if the restore
  picked the wrong tarball), extracts the tarball into `/var/lib/plex`,
  fixes ownership to `plex:plex`, restarts `plex.service`.
- Prints next steps (check `systemctl status plex`, open the web UI) on
  success.

## Implementation Steps
This is a `justfile`-only change (tooling, not a NixOS module) — the Module
Architecture Pattern (Option B) doesn't apply here, same as the earlier
`attic-bootstrap` recipe.

1. Add `backup-plex` and `restore-plex` recipes to `justfile`, ungrouped,
   placed directly after the existing `backup-now` recipe (same section,
   same style/guard pattern).

## Dependencies
None new — uses `tar`, `systemctl`, `chown`, all already available on every
NixOS system. No new packages, no new flake inputs.

## Configuration Changes
None — no new Nix options.

## Risks and Mitigations
- **Risk:** restoring over live, differently-versioned Plex data could
  corrupt the database. **Mitigation:** stop the service first, and preserve
  the pre-restore state as a `.bak-<timestamp>` directory instead of
  deleting it, so a bad restore is recoverable.
- **Risk:** running restore without realizing it's destructive.
  **Mitigation:** typed `yes` confirmation gate before any data is touched.
- **Risk:** ownership mismatch after extraction breaks Plex on restart
  (tar preserves the *source* machine's UID/GID, which may not match the
  destination's `plex` user). **Mitigation:** explicit `chown -R plex:plex`
  after extraction, using the live system's actual `plex` user/group rather
  than hardcoded UIDs.
- **Risk:** interrupted backup leaves Plex stopped. **Mitigation:** `trap`
  ensures `plex.service` is restarted even if the tar command fails.

## Verification Plan
1. `just --list` — confirms justfile still parses cleanly (syntax check;
   this repo has no NixOS module changes to dry-build for a justfile-only
   change).
2. `bash scripts/preflight.sh` — full gate, unaffected by this justfile-only
   change but run anyway per Phase 6.
3. Manual read-through of both recipes for shell correctness (`set -euo
   pipefail`, quoting, trap ordering) since there is no live Plex install in
   this evaluation environment to actually execute against.
