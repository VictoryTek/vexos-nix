# NAS-to-NAS Mirror Sync — Specification

## Current State Analysis

- The user currently backs up their media collection manually: boots a VM,
  opens **Grsync** (a GUI wrapper over `rsync`), and runs a saved session
  named `tv` that mirrors `/goliath/data/media/tv/` →
  `/megatron/data/media/tv/` with these options (from the provided
  screenshots):
  - Basic: Preserve time, Preserve permissions, Preserve owner, Preserve
    group, Delete on destination, Verbose, Show transfer progress
  - Advanced: Keep partially transferred files, Protect remote args
  - Extra: no pre/post commands, no "halt on failure", not run as superuser
- `goliath` and `megatron` are two separately mounted NAS shares (mounted
  as local filesystem paths on the VM that runs the sync today). Nothing in
  this repo currently declares those specific mountpoints — they are
  host-specific and would be declared the same way any other remote share is
  today, via `vexos.storage.remote` (`modules/storage-remote.nix`,
  populated by `just attach-remote-storage`) or a plain local `fileSystems`
  entry if mounted some other way.
- `modules/server/` already has an established pattern for opt-in service
  modules with their own `vexos.server.<name>.enable` flag
  (`modules/server/default.nix` imports them all under one umbrella, active
  on both the `server` and `headless-server` roles).
- Precedent for the pieces this feature needs already exists in-repo:
  - **Scheduled systemd unit + failure notification**: `modules/server/snapraid.nix`
    (`systemd.services.snapraid-sync.onFailure = [ "notify-failure@snapraid-sync.service" ];`)
    and `modules/notify.nix` (generic `notify-failure@` template → ntfy).
  - **Ordering a unit after its storage mount(s)**: `modules/lib/storage-mount-ordering.nix`,
    consumed by `modules/server/jellyfin.nix` et al. via
    `RequiresMountsFor`.
  - **Low-priority background I/O for a bulk job**: `modules/server/kernel-builder.nix:110-111`
    sets `Nice = 19; IOSchedulingClass = "idle";` on its systemd service —
    the same treatment a large recursive rsync job should get so it doesn't
    starve interactive services sharing the host.
  - **Per-service backup registration / opt-out**: `modules/server/backup.nix`
    requires every enabled `vexos.server.<name>` to either register backup
    paths or appear in `noBackupNeeded` with a reason (enforced by an
    assertion).
  - **Multi-instance declarative option pattern**: `modules/server/backup.nix`'s
    `servicePaths` (`attrsOf (listOf str)`) and `modules/server/snapraid.nix`'s
    `parityDisks` (`listOf submodule`) are the two established idioms for
    "one option that expands into N systemd units/settings."
- No existing module currently wraps `rsync` as a scheduled mirror job — this
  is new functionality, not a wrapper the codebase already half-has.

## Problem Definition

Replace the manual VM + Grsync workflow with a declarative, unattended NixOS
service: a scheduled `rsync` mirror from one mounted NAS path to another,
matching the exact transfer semantics of the user's existing Grsync session,
configurable per job (source, destination, schedule) so it can cover more
than just the `tv` library later without editing Nix code — only the host's
job list.

## Proposed Solution Architecture

New module: **`modules/server/nas-sync.nix`**, imported from
`modules/server/default.nix` (Option B: new file, no `lib.mkIf` role gating
— it's a new optional service like every other file in that directory,
activated the normal way via `vexos.server.nasSync.enable` in the host's
`server-services.nix`).

### Option shape

```nix
options.vexos.server.nasSync = {
  enable = lib.mkEnableOption "scheduled rsync mirror jobs between mounted NAS paths";

  jobs = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        source = lib.mkOption {
          type = lib.types.str;
          example = "/goliath/data/media/tv/";
          description = ''
            rsync source path. Include or omit the trailing slash exactly as
            you want rsync to interpret it (trailing slash = copy directory
            *contents*; no trailing slash = copy the directory itself) — this
            module passes the string through unchanged.
          '';
        };
        destination = lib.mkOption {
          type = lib.types.str;
          example = "/megatron/data/media/tv/";
          description = "rsync destination path. Same trailing-slash rule as source.";
        };
        deleteOnDestination = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = ''
            Mirror deletions: remove files from destination that no longer
            exist in source (rsync --delete). Matches the existing Grsync
            session's "Delete on destination" checkbox. Set false for a
            one-way accumulate-only copy.
          '';
        };
        extraRsyncOptions = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Additional raw rsync flags appended to the command.";
        };
        mediaMounts = storageMounts.mediaMountsOption;
        timerConfig = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = { OnCalendar = "daily"; Persistent = true; };
          description = "systemd timer schedule for this sync job.";
        };
      };
    });
    default = { };
    description = ''
      Named rsync mirror jobs. Each key becomes a
      "nas-sync-<name>.service"/".timer" pair. Populate per-host in
      server-services.nix, e.g.:

        vexos.server.nasSync.jobs.tv = {
          source = "/goliath/data/media/tv/";
          destination = "/megatron/data/media/tv/";
          mediaMounts = [ "/goliath" "/megatron" ];
        };
    '';
  };
};
```

### rsync flag mapping (parity with the existing Grsync session)

| Grsync option (checked) | rsync flag | Notes |
|---|---|---|
| Preserve time/permissions/owner/group | `-a` (archive) | archive mode implies these plus recursion + symlinks-as-symlinks + devices/specials when run as root |
| Delete on destination | `--delete` | gated by `deleteOnDestination`, default `true` |
| Verbose | `-v` | logged to the journal via the unit's stdout |
| Keep partially transferred files | `--partial` | |
| Protect remote args | `--protect-args` (also `-s`) | no-op for local-to-local paths but harmless; kept for exact parity |

**Deviation, surfaced explicitly:** "Show transfer progress" (`--progress`)
is dropped. That flag emits a per-file percentage/throughput line meant for
an interactive terminal; under systemd it would just bloat the journal with
no one watching it. `-v` already logs each file transferred, which is the
useful part for an unattended job. All other Grsync checkboxes in the
screenshots (checksum, compression, device preservation, hardlink/symlink
handling, backups, itemized changes, disable recursion, "do not leave
filesystem", "skip newer", "ignore existing", "only update existing",
"don't map uid/gid") were left unchecked in the source session, so no
corresponding flags are added.

Resulting command per job:

```sh
rsync -a --delete --partial --protect-args -v "<source>" "<destination>"
```
(`--delete` omitted when `deleteOnDestination = false`; `extraRsyncOptions`
appended after.)

### systemd unit generation

For each `name` in `cfg.jobs`:

```nix
systemd.services."nas-sync-${name}" = {
  description = "rsync mirror: ${name}";
  serviceConfig = {
    Type = "oneshot";
    ExecStart = "${pkgs.rsync}/bin/rsync -a ${lib.optionalString job.deleteOnDestination "--delete "}--partial --protect-args -v ${lib.escapeShellArgs ([ job.source job.destination ] ++ job.extraRsyncOptions)}";
    Nice = 19;
    IOSchedulingClass = "idle";
  };
  onFailure = [ "notify-failure@nas-sync-${name}.service" ];
  unitConfig = storageMounts.requiresMountsFor job.mediaMounts;
};

systemd.timers."nas-sync-${name}" = {
  description = "Run nas-sync-${name}.service on schedule";
  wantedBy = [ "timers.target" ];
  timerConfig = job.timerConfig;
};
```

`storageMounts` is `import ../lib/storage-mount-ordering.nix { inherit lib; }`,
reused exactly as `jellyfin.nix` uses it — the job doesn't start until both
the source and destination mounts (declared in `mediaMounts`) are present,
correctly triggering automount-based remote shares instead of racing them.

### Failure notification

Reuses the existing generic template (`modules/notify.nix`) — no new
notification plumbing needed, matching the pattern already used by
`backup.nix` and `snapraid.nix`.

### Backup registration

`nasSync` performs no local data retention of its own (it mirrors another
NAS's live data, not a `/var/lib` state directory), so it belongs in
`backup.nix`'s `noBackupNeeded` list, not `servicePaths`. This requires a
one-line addition to `modules/server/backup.nix`'s existing
`noBackupNeeded` list (under "Not a data service"), otherwise `backup.nix`'s
assertion fails the build the moment `nasSync.enable = true` on a host that
also has `vexos.server.backup.enable = true`.

### `default.nix` registration

Add `./nas-sync.nix` to `modules/server/default.nix`'s import list, grouped
with the existing storage-tier entries (`mergerfs.nix`, `snapraid.nix`,
`../storage-remote.nix`) since it's the same storage domain.

## Implementation Steps

1. Create `modules/server/nas-sync.nix` per the option/config shape above.
2. Add `./nas-sync.nix` to the "Storage Tiers" section of
   `modules/server/default.nix`'s import list.
3. Add `"nasSync"` to `noBackupNeeded` in `modules/server/backup.nix`
   (with a one-line reason comment, matching the existing entries' style).
4. No host-specific job needs to be added to the repo itself — `jobs`
   defaults to `{ }` — but the spec documents the example the user would add
   to their own `server-services.nix`:
   ```nix
   vexos.server.nasSync.jobs.tv = {
     source = "/goliath/data/media/tv/";
     destination = "/megatron/data/media/tv/";
     mediaMounts = [ "/goliath" "/megatron" ];
   };
   ```
   This is left to the user because `/goliath` and `/megatron` are
   host-specific mount paths not currently declared anywhere in this repo —
   whether they should be added as `vexos.storage.remote` entries or are
   already mounted some other way on the sync host is outside this repo's
   visibility and outside the scope of "add the sync service."

## Dependencies

- `pkgs.rsync` — already in nixpkgs, no version pinning concerns, no new
  flake input. Context7 lookup not applicable (no external library/API
  surface, just a CLI already packaged in nixpkgs).

## Configuration Changes

- New option namespace: `vexos.server.nasSync.{enable,jobs.<name>.*}`.
- One-line addition to `modules/server/backup.nix`'s `noBackupNeeded`.
- One-line addition to `modules/server/default.nix`'s import list.
- No changes to `flake.nix`, no new flake inputs, no `stateVersion` impact.

## Risks and Mitigations

- **`--delete` is destructive if source/destination are misconfigured.**
  Mitigated by: matching the user's already-validated Grsync settings
  exactly (default `true`, same as their manual session), keeping
  `deleteOnDestination` as an explicit per-job override, and requiring the
  user to supply exact source/destination paths themselves (no
  auto-derivation/guessing of NAS paths by this module).
- **First run against a host where `/goliath`/`/megatron` mounts aren't
  declared yet** would fail closed rather than silently operate on the
  wrong (empty/local) path — `RequiresMountsFor` (via `mediaMounts`) makes
  the unit wait for/require the declared mountpoints instead of starting
  regardless.
- **Long-running large transfers competing with interactive services** —
  mitigated with `Nice = 19` / `IOSchedulingClass = "idle"`, matching the
  precedent in `kernel-builder.nix`.
- **Multiple jobs racing the same destination disk** is left to the user's
  own `timerConfig` scheduling (stagger `OnCalendar` per job); not solved
  automatically, since job count/overlap is host-specific and unknown here.
