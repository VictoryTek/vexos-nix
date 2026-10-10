# remote_storage_media_group — Spec

## Current state
- `modules/storage-remote.nix` mounts NFS/CIFS shares with no ownership handling.
  CIFS mounts default to root-owned `0755`, so media service users (sonarr, …)
  cannot write: `Folder '/mnt/<srv>/<share>/…' is not writable by user 'sonarr'`.
- `scripts/attach-remote-storage.sh` writes entries with only
  `type/server/export/mountPoint[/credentialsFile]`.
- No `media` group exists anywhere in the repo (`grep users.groups` → only kiji-proxy).
- Native media service users come from upstream NixOS modules
  (`services.<svc>.user`, default = service name): sonarr, radarr, lidarr, bazarr,
  sabnzbd, qbittorrent, plex, jellyfin, audiobookshelf.
- **prowlarr** uses `DynamicUser = true` upstream (no static user to add to a group)
  and only talks to indexers — it never reads/writes the media tree. Not touched.
- Docker-based media modules (chaptarr, listenarr, sportarr, bookshelf, tautulli)
  already take explicit `userId`/`groupId` (PUID/PGID); out of scope here.

## Design
1. `storage-remote.nix`: new per-mount options `gid` and `uid`
   (`nullOr int`, default `null`). When any `gid` is set:
   - assertion: all set gids are identical (one shared group);
   - `users.groups.media.gid = <that gid>`.
2. CIFS, when `options == []` and `gid != null`: add `gid=<gid>`, `file_mode=0664`,
   `dir_mode=0775`, plus `uid=<uid>` only if `uid` is set. Explicit `options`
   override still wins entirely (unchanged semantics). NFS options unchanged.
3. Service modules (`arr.nix`, `plex.nix`, `jellyfin.nix`, `audiobookshelf.nix`):
   inside each service's existing enable block add
   `users.users.${config.services.<svc>.user}.extraGroups =
      lib.optional (config.users.groups ? media) "media";`
   The guard sits in the *value* (not around `users.users`) so attribute names stay
   static → no evaluation recursion; when no `media` group exists it is `[]`.
4. `attach-remote-storage.sh`: new step `[5/7]` asks for the NAS group id
   (numeric, blank to skip); rejects non-numeric, rejects a gid already used by a
   different local group (NixOS gid-uniqueness assertion would fail the rebuild),
   and rejects a gid different from one already in `storage-remote.nix` (module
   assertion). Writes `gid = N;` into the entry. NFS: prints the export-side note
   (TrueNAS Mapall / dataset ACL). Final output notes `just rebuild` + restarting
   the services (group membership is read at service start; unit files don't change
   so `switch` won't restart them).
   Old steps `[5/6]`,`[6/6]` renumber to `[6/7]`,`[7/7]`.
5. `detach-remote-storage.sh` needs no change: its `_field` parser only reads
   quoted values, so `gid = N;` is ignored.

## Option B compliance
No role gating added. `config.users.groups ? media` is a data-presence check
required by the request, not a role/display/gaming flag.

## Risks
- gid collides with a local group → caught in the script; NixOS asserts otherwise.
- NFS: nothing client-side fixes ownership; documented in script output.
- SMB fragility: only mount *options* on the CIFS fstab line change, and only when
  `gid` is explicitly set; discovery/Samba/avahi untouched.

## Validation
`nix flake show --impure`; eval/dry-build of one target per role (six roles);
scenario evals with a stub `vexos.storage.remote` (cifs+gid, nfs+gid, mismatched
gids, no gid); `bash scripts/preflight.sh`; `shellcheck` on the script.
