# remote_storage_owner_uid — Spec

## Current state
- `modules/storage-remote.nix` `cifsOwnership` emits `gid=`/`file_mode=0664`/`dir_mode=0775`
  (and `uid=` if set) **only when `gid != null`**. `uid` is silently ignored otherwise.
- `scripts/attach-remote-storage.sh` step 6 only asks "Let media services write?" and never
  writes `uid`. Result: the interactive user is neither owner nor in `media`, so the
  permanent CIFS mount is read-only for them (root-owned), unlike a GNOME/GVfs mount.
- `scripts/list-remote-storage.sh` shows only a `writers` line derived from `gid`.

## Problem
No way to make the permanent CIFS mount writable by the desktop user, regardless of the
media-services answer.

## Design
1. `modules/storage-remote.nix`: `cifsOwnership` applies when `gid != null || uid != null`:
   `gid=` (if set) ++ `file_mode=0664`, `dir_mode=0775` ++ `uid=` (if set).
   gid-only output is unchanged. Update the `uid` option description (no longer needs `gid`).
   NFS and explicit `options` override unchanged.
2. `scripts/attach-remote-storage.sh` step 6 (CIFS only): before the media-services
   question, ask "Let <user> write to this share? [Y/n]" where <user> is `$SUDO_USER`
   (skipped with a note when unset/root). Y → `OWNER_UID=$(id -u $SUDO_USER)`, written as
   ` uid = N;` in the entry. Independent of the media answer. Reword the media text so it is
   clearly about services. Final summary notes the owner.
3. `scripts/list-remote-storage.sh`: add an `owner` line when `uid` is present.

## Not changed
`gid`/`media` group semantics, NFS flow, users.nix, service modules, flake inputs.

## Risks
- Local ownership is a label; the NAS account still decides real access (printed in the
  summary). Existing entries without `uid` render identically (no churn).
- Per project memory: SMB setup is fragile — change is additive and gated by the new prompt.
