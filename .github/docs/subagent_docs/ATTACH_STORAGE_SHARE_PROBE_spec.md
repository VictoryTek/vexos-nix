# ATTACH_STORAGE_SHARE_PROBE — spec

## Current state
`scripts/attach-remote-storage.sh` (run via `just remote-storage attach`) asks for
the storage server host/IP, then immediately asks for the NFS export path / CIFS
share name as free text (examples only: `/tank/media`, `media`). It never contacts
the server. CIFS credentials are collected afterwards (step 4) because the
credentials file is named after the mountpoint, which is only known once the share
has been chosen.

## Problem
The user has already supplied the server address; the script can ask the server
what it offers and present a menu instead of requiring the share name from memory.

## Proposed solution
After the server address is entered, probe it and show a numbered menu of the
discovered shares/exports plus a "type it manually" entry.

| Protocol | Probe                                      | Parse                                   | Package     |
|----------|--------------------------------------------|-----------------------------------------|-------------|
| nfs      | `showmount -e --no-headers <server>`       | first field of each line (export path)  | `nfs-utils` |
| cifs     | `smbclient -L //<server> -g -A <authfile>` | `Disk\|<name>\|<comment>` lines; drop `*$` | `samba`  |

Verified against `showmount --help` and the `smbclient(1)` man page on the
current host (`-g` grepable output, `-A` authentication file format
`username = / password =`).

Design decisions:
- **CIFS credentials move ahead of the share menu.** Most NAS units refuse to
  list shares to guests, and `modules/storage-remote.nix` already asserts that
  every cifs entry has a credentials file (anonymous mounts are not allowed), so
  the credentials are needed regardless. They are prompted right after the server
  address, held in shell variables, and the real
  `/etc/nixos/secrets/remote-<mnt>-credentials` file is still only written once
  the mountpoint is known. The probe uses a throw-away 0600 file inside a
  `mktemp -d` directory (0700) removed by an EXIT trap; the password never
  appears on a command line.
- **Missing probe tool** (nfs-utils/samba only land on rebuild): run it through
  `nix shell nixpkgs#<pkg> -c <bin> ...` (same mechanism `scripts/preflight.sh`
  already uses). If that fails (no network / cache), the probe yields nothing.
- **Fallback is the existing behaviour.** Probe failure, empty result, or the
  "type it manually" choice drops to today's typed prompt, so nothing regresses
  (NFSv4-only servers that do not answer `showmount` land here).
- **smbclient exit status is ignored**; it exits non-zero after printing the
  share list when the SMB1 workgroup-listing reconnect fails. Output is parsed.
- Steps renumbered `[3/6] Server (+ CIFS credentials)` and
  `[4/6] Share / mountpoint` so the 6-step layout is preserved.

## Derived mountpoint (added at user request)
The "Local mountpoint" prompt is gone. The mountpoint is
`/mnt/<server-name>/<share-name>`:
- `<server-name>`: mDNS hostname when the address was discovered, else the typed
  hostname with its domain dropped, else `nas-<ip with dashes>`.
- `<share-name>`: `basename` of the share/export.
- Both pass through `slug` (non `[A-Za-z0-9._]` runs → `-`).
- The prompt only reappears when the derived path is already claimed in
  `storage-remote.nix` (same share attached twice).
- CIFS credentials file is now `remote-<slug of full mountpoint>-credentials`
  (was `basename`, which would collide for `goliath/data` vs `other/data`).
  Existing entries are unaffected: they carry an explicit `credentialsFile`.
- `detach-remote-storage.sh` additionally `rmdir`s the empty `/mnt/<server>`
  parent after removing the share's mountpoint (never `/mnt` itself).

## Files
- `scripts/attach-remote-storage.sh`
- `scripts/detach-remote-storage.sh` (parent-dir tidy only)

No flake input, module, or option changes; the Option B module pattern is not
affected.

## Risks
- Probe parsing cannot be validated against a real NAS in the dev environment;
  mitigated by the manual fallback and by testing the parsers with captured
  sample output.
- `nix shell` fallback needs network on first use; mitigated by the fallback.
