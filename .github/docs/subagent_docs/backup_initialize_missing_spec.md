# modules/server/backup.nix: restic repository never auto-initializes — Spec

## Current state analysis

`modules/server/backup.nix:174-188` configures `services.restic.backups.main` by
inheriting a subset of `vexos.server.backup.*` options:

```nix
services.restic.backups.main = {
  inherit (cfg) repository repositoryFile pruneOpts timerConfig;
  passwordFile = lib.mkIf (cfg.passwordFile != null) (toString cfg.passwordFile);
  paths = enabledServicePaths ++ cfg.extraPaths
    ++ lib.optional config.services.postgresql.enable postgresDumpFile;
  backupPrepareCommand = lib.mkIf config.services.postgresql.enable ''...'';
  backupCleanupCommand = lib.mkIf config.services.postgresql.enable ''...'';
};
```

The upstream nixpkgs `services.restic.backups.<name>.initialize` option
(`nixos/modules/services/backup/restic.nix`) defaults to `false`:

```nix
initialize = lib.mkOption {
  type = lib.types.bool;
  default = false;
  description = "Create the repository if it doesn't exist.";
};
```

When `initialize = true`, the generated `preStart` for the
`restic-backups-<name>.service` unit includes:

```sh
restic cat config > /dev/null || restic init
```

When `initialize` stays `false` (as it currently does here, since nothing sets it),
that line is omitted from `preStart` entirely — confirmed empirically: the actual
generated preStart script on a test VM is just:

```sh
#!/nix/store/.../bin/bash
set -e

cat /nix/store/.../staticPaths >> /run/restic-backups-main/includes
```

No init logic at all. As a result, `restic backup` (the main `ExecStart`) always
fails with `Fatal: repository does not exist` on a fresh repository path, since
nothing ever creates it — this reproduced identically on both the daily timer's
first (`Persistent`) catch-up run and a manual `systemctl start`.

## Problem definition

`vexos.server.backup.enable = true` (whether set manually via `just enable backup`
or auto-set via `_ensure_backup_defaults` in the justfile) never results in a
working backup on a fresh repository path, because the restic module's
`initialize` option is never turned on. Every first-time enable, on any storage
target (local disk, remote, etc.), will fail identically until someone manually
runs `restic init` out-of-band.

## Proposed solution

Set `initialize = true;` in the `services.restic.backups.main` block in
`modules/server/backup.nix`, alongside the existing `inherit`. This is the single
missing line — `restic cat config > /dev/null || restic init` is idempotent and
safe to run on every backup invocation (a no-op once the repo already exists), so
there's no reason to gate it further or make it configurable; matches how the
upstream module's own example config uses `initialize = true` for exactly this
"repo may not exist yet" scenario.

## Implementation steps

In `modules/server/backup.nix`, inside the `services.restic.backups.main = { ... }`
block (~line 174-188), add:

```nix
initialize = true;
```

Minimal, single-line, surgical change — no other structure in the file needs to
change. No new options, no new module, no Module Architecture Pattern
implications (this is a value inside an existing `lib.mkIf cfg.enable { ... }`
block, not a new shared/role file).

## Dependencies

None — pure NixOS module config, no external library, no Context7 lookup needed.

## Configuration changes

None beyond the one-line addition above. No option surface changes, no
`server-services.nix` template changes needed (the option already exists
upstream; it just wasn't being set).

## Risks and mitigations

- **Risk:** none — `restic init` on an already-initialized repo is a no-op check
  (`restic cat config` succeeds first, short-circuiting the `||`).
- **Risk:** first backup run for existing hosts that had backups silently failing
  will now actually initialize and start working — this is the intended fix, not
  a regression.
- **Out of scope:** the disposable test VM's already-broken half-state does not
  need remediation (user confirmed disposable). After the fix + rebuild, the next
  scheduled or manual `restic-backups-main.service` run will self-heal by creating
  the repository.
