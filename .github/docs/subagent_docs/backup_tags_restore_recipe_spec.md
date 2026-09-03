# Backup snapshot tags + `just restore-service` recipe — Spec

Feature name: `backup_tags_restore_recipe`
Phase 1 — Research & Specification

---

## 1. Current state analysis

### Backup module (`modules/server/backup.nix`)

- `vexos.server.backup` is opt-in; when enabled it configures a single
  `services.restic.backups.main` whose `paths` is the union of every enabled
  service's registered `servicePaths` plus `extraPaths` (plus an optional
  postgres dump).
- Result: **one snapshot per daily run, containing every enabled service's data
  directory.** There is no per-service snapshot, no tag, and no on-disk record of
  which path belongs to which service.
- `services.restic.backups.<name>.createWrapper` defaults to `true` (verified
  against nixpkgs unstable via the nixos MCP), so a root-only wrapper
  `restic-main` is already on `PATH` with `RESTIC_REPOSITORY` /
  `RESTIC_PASSWORD_FILE` / etc. pre-set. Nothing in vexos uses it yet.
- The nixpkgs restic module has **no `tags` option** (verified — 26 options, none
  named `tags`). Tags are set through `extraBackupArgs = [ "--tag" ... ]`.
- `initialize = true` is already set (fixed in `backup_initialize_missing`).

### Path registration data already in the module

```nix
enabledServicePaths = lib.flatten (
  lib.mapAttrsToList
    (name: paths: lib.optionals (config.vexos.server.${name}.enable or false) paths)
    cfg.servicePaths);
```

The name→paths association exists at eval time but is flattened away. A
`lib.filterAttrs` over `cfg.servicePaths` keeps it.

### Justfile

- `backup-now` (≈ line 1786) — `sudo systemctl start restic-backups-main.service --wait`.
- `backup-plex` / `restore-plex` (≈ line 1798–1879) — the established pattern for
  a destructive restore recipe: `_require-server-role` dependency, typed-`yes`
  confirmation honouring `VEXOS_ASSUME_YES=1`, stop unit + `trap ... EXIT`
  restart, preserve existing data, `echo "✓ ..."` completion.
- These three recipes carry **no `[group(...)]` attribute** and are not
  `[private]`.
- `jq` is **not** in `modules/packages-common.nix` and not guaranteed on server
  roles (only `modules/development.nix` and `modules/hyprland-desktop.nix` pull
  it in). `coreutils`/`gnugrep`/`gawk` are always present.

---

## 2. Problem definition

With one combined snapshot, the operator has no first-class way to (a) see which
services a snapshot covers or (b) restore a single service without hand-writing
`restic restore latest --include /var/lib/<x> --target /` and first working out
the correct data path and the correct restic environment.

Two gaps:

1. **No snapshot tags.** `restic snapshots --tag <service>` cannot answer "which
   snapshots contain uptime-kuma".
2. **No restore ergonomics.** No recipe equivalent to `restore-plex` for the
   declarative backup set.

---

## 3. Proposed solution architecture

### 3.1 Tag every snapshot with its covered services

In the `services.restic.backups.main` block, add:

```nix
extraBackupArgs =
  let tags = [ "vexos" ] ++ enabledBackupServices;
  in lib.concatMap (t: [ "--tag" t ]) tags;
```

where, in the `let` block at the top of the file:

```nix
enabledBackupServices = lib.filter
  (name: config.vexos.server.${name}.enable or false)
  (lib.attrNames cfg.servicePaths);
```

`lib.attrNames` is sorted, so the argument list is deterministic (no rebuild
churn). Every snapshot then carries `vexos` + one tag per service actually
included in that run. Newly-enabled services are absent from older snapshots'
tags, which is correct — `restore latest --tag <name>` then resolves to the most
recent snapshot that actually contains that service.

This does **not** change storage layout, snapshot count, dedup, or retention.

### 3.2 Emit a service→paths manifest

Inside the existing `lib.mkIf cfg.enable` block:

```nix
environment.etc."vexos/backup-paths.json".text = builtins.toJSON
  (lib.filterAttrs (name: _: config.vexos.server.${name}.enable or false)
    cfg.servicePaths);
```

Produces e.g. `/etc/vexos/backup-paths.json`:

```json
{"jellyfin":["/var/lib/jellyfin"],"uptime-kuma":["/var/lib/private/uptime-kuma"]}
```

Only enabled services appear — matching exactly what is in the snapshots.
`extraPaths` and the postgres dump are intentionally excluded: they are not
service-scoped and the recipe is a per-service tool. (Documented in a module
comment.)

### 3.3 `pkgs.jq` for the manifest consumer

Add to the `lib.mkIf cfg.enable` config:

```nix
environment.systemPackages = [ pkgs.jq ];
```

`jq` is the manifest parser for the restore recipe. Scoping it to
`cfg.enable` keeps the dependency next to the feature that needs it rather than
widening `packages-common.nix` for all roles (Option B: the feature carries its
own additions). Requires adding `pkgs` to the module's argument set
(`{ config, lib, pkgs, ... }`).

### 3.4 `just restore-service <name> [snapshot]`

New recipe placed immediately after `restore-plex`, same attribute shape (no
group, not private), `_require-server-role` dependency.

Behaviour:

1. Resolve `restic-main` wrapper: `command -v restic-main` — hard error with
   "enable backups with `just enable backup && just rebuild`" if absent. (Wrapper
   name is `restic-${name}` in nixpkgs; `main` is our backup set name.)
2. Require `/etc/vexos/backup-paths.json`; hard error → "rebuild after enabling
   backups" if missing.
3. `mapfile -t PATHS < <(jq -r --arg n "$NAME" '.[$n][]?' "$MANIFEST")`.
   If empty: print `error: '<name>' has no backup paths registered` followed by
   `jq -r 'keys[]'` (the known service list), exit 1.
4. Print the snapshot, the resolved tag, and the target paths; warn that files
   are overwritten in place (restic restore does not delete files absent from the
   snapshot — no `.bak` move, unlike `restore-plex` which extracts a whole tar).
5. Typed-`yes` confirmation, satisfied by `VEXOS_ASSUME_YES=1` (matches
   `restore-plex`).
6. If `<name>.service` exists and is active: `sudo systemctl stop` it and
   `trap 'systemctl start' EXIT`. Services with no matching unit name (or
   inactive) are simply restored without a stop.
7. `sudo "$(command -v restic-main)" restore "$SNAP" --tag "$NAME" --target / \
   --include <p1> [--include <p2> …]`
   `sudo "$(command -v …)"` form because `sudo` resets `PATH` and the wrapper
   lives in `/run/current-system/sw/bin`.
8. `echo "✓ Restore complete for '<name>'."` plus a "check status" line.

`snapshot` parameter defaults to `latest`; an explicit snapshot ID (from
`restic-main snapshots`) can be passed for point-in-time restore.

---

## 4. Implementation steps

1. `modules/server/backup.nix`
   - `{ config, lib, ... }` → `{ config, lib, pkgs, ... }`.
   - Add `enabledBackupServices` to the `let` block.
   - In `services.restic.backups.main`: add `extraBackupArgs` (tags).
   - In the `lib.mkIf cfg.enable` attrset: add `environment.etc."vexos/backup-paths.json"`
     and `environment.systemPackages = [ pkgs.jq ]`.
   - Add a short comment block explaining the manifest and the tag scheme.
   → verify: `nix flake show --impure` clean; `nixos-rebuild dry-build` for
     `vexos-server-amd` and `vexos-headless-server-amd` succeeds; `nix eval` of
     `...main.extraBackupArgs` shows the expected `--tag` list for a config with
     two services enabled.

2. `justfile`
   - Add `restore-service` recipe after `restore-plex` (ends ≈ line 1879).
   → verify: `just --list` shows `restore-service`; `just --fmt --check` passes if
     the repo uses it (check first); manual read-through of the bash for
     `set -euo pipefail`, quoting, and `VEXOS_ASSUME_YES` handling.

3. Docs
   - Update the `just enable backup` epilogue text (≈ line 2890) and/or the
     `backup-now` area to mention `restore-service` and
     `restic-main snapshots --tag <service>`.
   → verify: grep for the new recipe name in the help text.

No `configuration-*.nix`, `hosts/`, or `flake.nix` changes. No
`system.stateVersion` impact. No new flake input.

---

## 5. Dependencies

- `pkgs.jq` — already in nixpkgs, no version pin needed, no Context7 lookup
  (not a versioned external API; it is a nixpkgs package).
- `restic` wrapper — provided by the nixpkgs restic module already in use.
- No new flake inputs, so no `follows` declaration needed.

---

## 6. Configuration changes

- New read-only file on enabled backup hosts: `/etc/vexos/backup-paths.json`.
- Every restic snapshot gains `--tag vexos` + per-service tags. Existing
  snapshots are unaffected (tags apply at creation time); the first run after the
  rebuild starts the new tagging.
- `jq` added to system packages on hosts with `vexos.server.backup.enable = true`.

---

## 7. Risks and mitigations

| Risk | Mitigation |
|------|-----------|
| `restic-main` wrapper name wrong for this nixpkgs | Recipe probes with `command -v` and fails loudly with remediation text; reviewer confirms actual name via `nix eval`/dry-build introspection or nixpkgs source in Phase 3. |
| `extraBackupArgs` ordering non-deterministic → rebuild churn | `lib.attrNames` is lexicographically sorted; tag list is a pure function of enabled service set. |
| Restore into `/` as root overwrites live data with no undo | Typed-`yes` confirm; service stopped first; message states "overwritten in place"; explicit snapshot arg enables safer restore-to-alt-path by the operator if desired (documented). |
| `jq` widening closure on server roles | `jq` is ~1–2 MB, pulled only when backups are enabled; smaller footprint than adding to `packages-common.nix`. |
| Service data path not under a stoppable `<name>.service` (e.g. container, `-private` dynamic dir) | Recipe stops the unit only when it exists and is active; restic writes the path regardless. `DynamicUser` paths under `/var/lib/private` are captured verbatim from the manifest. |
| Manifest lists a path but service was disabled between backup and restore | `--tag <name>` selects the latest snapshot that still had the service; if none, restic exits non-zero and the recipe surfaces it. |

---

## 8. Out of scope

- Per-service independent snapshots / retention (would require one
  `services.restic.backups.<name>` per service — the user explicitly chose to
  keep the single combined repo).
- Restoring `extraPaths` or the postgres dump (not service-scoped).
- A `list-backups` / snapshot browser recipe (can be added later;
  `restic-main snapshots` already works).
