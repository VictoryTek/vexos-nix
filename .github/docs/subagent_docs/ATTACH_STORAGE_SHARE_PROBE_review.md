# ATTACH_STORAGE_SHARE_PROBE — review

Modified: `scripts/attach-remote-storage.sh` (only file). Spec:
`ATTACH_STORAGE_SHARE_PROBE_spec.md`.

Scope note: the spec was extended mid-flight at the user's request to include
LAN server discovery (mDNS via `avahi-browse`, `_smb._tcp` / `_nfs._tcp`) ahead
of the share probe. Discovery needs no new package: avahi is enabled in
`modules/network.nix` for every role.

## Verification performed
| Check | Result |
|-------|--------|
| `bash -n` | clean |
| `shellcheck -S warning` | clean |
| Harness of steps 3–4, fake `showmount` / `smbclient` | NFS menu, CIFS menu, probe-failure fallback, invalid input, `m` manual entry all behave |
| Real `avahi-browse` on this LAN | 1 NFS + 3 SMB hosts listed; `\032`/`\091` escapes decoded; own IPs skipped |
| smbclient auth file | created 0600 inside a 0700 `mktemp -d`; password not on argv; removed by EXIT trap |
| `scripts/preflight.sh` | exit 0, all hard stages pass (Nix-format warning is pre-existing; no `.nix` file touched) |
| `hardware-configuration.nix` tracked | no |
| `system.stateVersion` | untouched |

## Not verified
- Parsing of real `showmount` / `smbclient -L -g` output from an actual NAS
  (fake tools mirror the documented formats only).
- The `nix shell nixpkgs#samba|nfs-utils` fallback when the tool is absent.
- No Nix modules changed, so only the preflight's current-variant dry-build was
  run, not the per-role dry-build matrix.

## Findings
- No CRITICAL issues.
- Behaviour change to note: CIFS username/password are now asked right after
  the server is chosen (before the share menu) rather than after the mountpoint.

**Result: PASS**
