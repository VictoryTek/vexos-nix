# legacy-migration/

One-off tooling for migrating a host running raw `docker-compose` stacks
onto proper `vexos.server.<name>` modules (native or OCI). This is **not**
part of ongoing VexOS operation — it exists for the transition period only,
kept here in case another legacy Docker host needs the same treatment in
the future.

## Files

| File | Purpose |
|---|---|
| `backup-stacks-v2.sh` | Backs up every docker-compose stack on the old host |
| `restore-stacks.sh` | Restores generic (DB-backed) backups on the new host |
| `services.conf` | Optional per-service override for apps with a real built-in export feature |

## Assumptions

- Each service lives under `STACKS_DIR` (default `/opt/stacks/<name>/`) with
  its own `docker-compose.yml` — the compose-per-service convention.
- You have `sudo`/root on the host (needed for `docker compose down/up` and
  to set correct ownership on the backup output).
- Docker (not Podman) is the backend on the legacy host.

## Usage: backing up the old host

```bash
cd ~/Documents/legacy-migration   # or wherever you copied this dir
chmod +x backup-stacks-v2.sh
sudo ./backup-stacks-v2.sh
```

Edit the variables at the top of the script first if your setup differs
from the defaults:

- `STACKS_DIR` — where your compose stacks actually live
- `BACKUP_DIR` — local path with enough free space for all archives
- `DO_REMOTE_SYNC` — off by default; backups stay local. See "Getting
  backups off the host" below.

**Ownership**: the script runs under `sudo`, so it automatically hands
ownership of everything in `BACKUP_DIR` back to the user who invoked
`sudo` (via `$SUDO_USER`) once it finishes — you shouldn't need `sudo` to
read or copy the resulting files afterward.

**Output**: one `.tar.gz` per service in `BACKUP_DIR`, plus:
- `manifest.csv` — per-service status (method used, backup success,
  archive success). **Check this for any `FAILED` entries before wiping
  the host.**
- `backup.log` — full run log.
- `services.conf` — a copy of whatever manifest was used, saved alongside
  the backups for reference during restore.

### services.conf — optional built-in export overrides

By default every service is backed up generically: auto-detect a
postgres/mysql/mariadb/redis container in its compose stack, dump it, and
tar the whole stack directory (compose file, `.env`, bind mounts, dump).
This is fine for most services and requires no configuration.

`services.conf` is only needed for a service that has its **own** proper
backup/export feature you'd rather use instead (e.g. Mealie's built-in
export). It's a plain pipe-delimited file — see the comments in the
template for the exact format. Any service not listed in it just uses the
generic method automatically.

Running the generic backup on top of a service you've already exported
manually is harmless and actually a good idea — you end up with two
independent backups of the same data (the app's native export, plus a raw
DB dump), which is strictly safer before wiping a host, not redundant
waste.

### Getting backups off the host

`DO_REMOTE_SYNC` is off by default — the script never auto-copies
anywhere. At the end of a run it prints the exact command to copy
`BACKUP_DIR` to wherever you're keeping the offsite copy, e.g.:

```bash
rsync -avz --progress /path/to/BACKUP_DIR/ /path/to/nas-or-usb-mount/vmc01-migration/
```

Verify the copy landed and `manifest.csv` is clean before reimaging the
host.

## Usage: restoring on the new host

**Current capability**: `restore-stacks.sh` handles the **generic** path
only — extracting each archive and restoring an auto-detected
postgres/mysql/redis dump into a freshly-started db container of the same
image.

**Known limitation**: it does **not** yet automate restoring a
`services.conf` "builtin" export (e.g. Mealie's own export file, sitting
in that service's `app-backup/` folder inside its archive). For any
service backed up via the builtin method, restore it manually using the
`restore_cmd` you recorded for it in `services.conf` at backup time —
that field exists specifically so you have the right command on hand when
you get to this step, even though the script doesn't run it for you yet.

```bash
sudo ./restore-stacks.sh
```

Edit `INCOMING_DIR` / `STACKS_DIR` at the top first to match the new
host's layout.

## Why this isn't a permanent part of vexos-nix

This tooling exists to solve a temporary problem: getting data off hosts
that predate the module system. Once a host is fully migrated, its
services are managed declaratively and get backup coverage "for free"
through `vexos.server.backup`'s self-registering `servicePaths` — none of
this script is needed for that host again. It's kept in the repo purely
as a reusable reference for the next legacy host, not as an
ongoing-maintenance tool.