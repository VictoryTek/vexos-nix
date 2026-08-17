# plex_storage_mount_ordering — Spec

## Current State Analysis

`modules/server/plex.nix` enables `services.plex` with no ordering dependency on
any storage mount. `plex.service` is pulled in by `multi-user.target` like any
other service and has no `After=`/`RequiresMountsFor=` relationship to the
filesystem(s) backing the user's media libraries.

Two storage tiers exist in this repo, both declared via NixOS `fileSystems`
(so both are ultimately backed by real systemd `.mount`/`.automount` units):

- **Local**: `modules/server/mergerfs.nix` (union pool at
  `vexos.server.storage.mergerfs.mountPoint`, default `/storage`) or a ZFS
  pool (`modules/zfs-server.nix` + `just create-zfs-pool`).
- **Remote**: `modules/server/storage-remote.nix` — NFS/CIFS client mounts
  populated by `just attach-remote-storage`, deliberately mounted with
  `_netdev nofail x-systemd.automount` so a slow/offline NAS never blocks
  boot; the mount only actually happens on first access to the path.

`mergerfs.nix` already uses the systemd `requires-mounts-for` idiom for
ordering the union mount after its branch disks (line 55:
`x-systemd.requires-mounts-for=${b.mountPoint}`), but nothing orders
**service** units (Plex, or any other consumer) after the mount they read
from.

## Problem Definition

When the storage tier isn't yet ready — most commonly the automount unit for
a remote NAS mount hasn't been set up yet during a fast boot/restart, or the
mergerfs/ZFS pool is still coming up — `plex.service` starts anyway (nothing
orders it after the mount). Plex then either sees an empty/missing library
path or opens the path before the automount plumbing is watching it, and
marks the library unavailable. Recovery today is manual: the user must wait
for the NAS/pool to be confirmed up, then restart Plex.

## Proposed Solution

Add an opt-in option to `modules/server/plex.nix` that lets the operator
declare which mountpoint(s) back their Plex libraries, and wire it to the
standard systemd `RequiresMountsFor=` unit directive. This is the mechanism
systemd documents for exactly this case (services that read from a path that
may be backed by an automount unit): it adds `Requires=`/`After=` on whatever
mount unit governs that path, so:

- **Local pools** (mergerfs / ZFS, mounted synchronously during boot):
  `plex.service` is ordered to start only after that mount unit reports
  active. If the mount unit fails, Plex correctly fails to start too, instead
  of silently starting against an empty directory.
- **Remote pools** (`storage-remote.nix`, automount-based): `plex.service` is
  ordered after the automount unit is set up and watching the path. The
  actual NFS/CIFS mount still happens transparently on first access (that's
  the automount contract — kernel autofs blocks the accessing process until
  the mount completes), but because the automount unit is now guaranteed to
  exist and be armed before Plex starts, Plex's first access correctly
  triggers-and-blocks instead of racing an unarmed path.

This is generic across both storage tiers because `RequiresMountsFor`
resolves an arbitrary path to whichever `fileSystems`-derived unit owns it —
no branching logic needed in `plex.nix` for "local vs remote".

### Implementation Steps (Option B module pattern)

`plex.nix` is a role-agnostic, single-purpose service module — this is a
same-module option addition (the module's own `enable`-gated config), not a
role split, so no new file is needed (matches the existing carve-out for
toggleable subsystems in a module's own config).

1. Add `vexos.server.plex.mediaMounts` (`listOf str`, default `[ ]`) to
   `modules/server/plex.nix`: absolute path(s) the operator's Plex libraries
   live under (e.g. `[ "/mnt/nas-media" ]` or `[ "/storage" ]`).
2. When non-empty, set
   `systemd.services.plex.unitConfig.RequiresMountsFor = lib.concatStringsSep " " cfg.mediaMounts;`
3. Default stays `[ ]` (no ordering change) — this is opt-in because
   `plex.nix` cannot know the operator's library layout, and a host with
   fully local (non-pooled) storage under `/var/lib/plex` needs no ordering
   dependency at all.
4. No assertions needed — an empty list is a valid, common configuration
   (e.g. all-local, disk-backed hosts).

### Configuration Example

```nix
vexos.server.plex.enable = true;
vexos.server.plex.mediaMounts = [ "/mnt/nas-media" ];  # or "/storage" for local mergerfs/ZFS
```

## Dependencies

None — pure NixOS/systemd unit configuration (`unitConfig.RequiresMountsFor`
is a standard `systemd.service` freeform passthrough, already used in this
repo at `modules/virtualization.nix:41`). No new packages, no Context7
lookup required (internal-only change, matches CLAUDE.md's "Context7 NOT
required" carve-out for internal changes with no new dependencies).

## Risks and Mitigations

- **Risk**: operator sets `mediaMounts` to a path NOT covered by any
  `fileSystems` entry (e.g. a typo, or a path that's just a subdirectory of
  local disk with no dedicated mount). **Mitigation**: `RequiresMountsFor` on
  a path with no matching mount unit is a systemd no-op (falls back to no
  added dependency) — safe by default, not a hard failure. Documented in the
  option description so operators point it at an actual mountpoint.
- **Risk**: local mount unit failing (e.g. a bad disk) now blocks
  `plex.service` from starting at all, where previously it would start
  against a broken/empty path. **Mitigation**: this is the intended,
  correct behavior — failing loudly (Plex won't start) is preferable to
  silently starting against missing media and requiring the same manual
  "confirm NAS is up, restart Plex" recovery the user is trying to eliminate.
- **Out of scope**: applying the same pattern to other media-adjacent
  services (jellyfin, immich, navidrome, komga, kavita, audiobookshelf,
  tautulli, seerr, arr.nix). Not touched here per CLAUDE.md's surgical-change
  rule — the user's request named Plex specifically. The same
  `mediaMounts`-style option can be added to any of those modules later using
  this same pattern if needed.
