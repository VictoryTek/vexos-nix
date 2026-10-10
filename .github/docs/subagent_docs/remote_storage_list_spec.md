# remote_storage_list — Spec

## Current state
- `just remote-storage` menu (justfile `remote-storage` recipe, `_menu` helper) has
  `attach` and `detach`. There is no way to see what is already attached other than
  opening `/etc/nixos/storage-remote.nix` or running `detach` and backing out.
- Attached shares live as one-line entries between the
  `# >>> vexos-remote-entries >>>` / `# <<< vexos-remote-entries <<<` markers in
  `/etc/nixos/storage-remote.nix` (type, server, export, mountPoint,
  credentialsFile for CIFS, gid when write access was enabled).
- `_menu` supports read-only items via a 4th field (`key|desc|prompt|stay`): picked
  from the menu they run and return to the menu instead of exiting.

## Design
1. New `scripts/list-remote-storage.sh` — read-only, never mounts, never writes,
   does not require root. Parses the managed entries with the same markers/`_field`
   idiom as `detach-remote-storage.sh` and prints, per entry: protocol,
   `server:export`, local mountpoint, live status, write group (gid) if any, and the
   CIFS credentials file path (path only, never contents).
   Status is derived without triggering the automount (a stat on the mountpoint would
   mount it and could block on an offline NAS):
   - `findmnt -t nfs,nfs4,cifs --mountpoint <mp>` → **mounted** (+ `timeout 5 df`
     size/used/free);
   - else the `<escaped-mp>.automount` unit is active → **idle** (mounts on first access);
   - else → **not applied yet** (declared, run `just rebuild`).
   No entries / no file → a one-line "nothing attached" message with the attach hint.
2. justfile: `_remote-storage-list` recipe (same `_require-remote-storage-role` guard,
   dispatched through the shared `_run-storage-script` like attach/detach) and a new
   `list|…||stay` item appended to the `remote-storage` menu (appended last so existing
   menu numbers 1/2 do not shift).

## Option B / scope
No Nix module change. No flake change. Surgical: one new script, one recipe, one menu
item (+ the recipe's doc comment).

## Risks
- Entries hand-edited outside the markers are not shown — same limitation as detach.
- `df` on a hung NFS mount: bounded by `timeout 5`.

## Validation
`bash -n` + shellcheck; run the script against a fixture `storage-remote.nix`
(path substituted in a scratch copy) covering: absent file, empty markers, NFS+gid,
CIFS+gid, entry not mounted/not applied; `just --list` / `just remote-storage list`
parse; `bash scripts/preflight.sh`.
