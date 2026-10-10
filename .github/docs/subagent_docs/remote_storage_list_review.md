# remote_storage_list — Review

Result: **PASS** (no refinement cycle needed)

## Spec compliance
Implemented as specified: `scripts/list-remote-storage.sh` (read-only, root not
required), `_remote-storage-list` recipe, and a `list|…||stay` item appended last in the
`remote-storage` menu so existing numbers 1/2 are unchanged. No Nix module or flake change.

## Validation
- `bash -n`, shellcheck (default severity) clean on the new script.
- `just --evaluate` parses; `just --list` shows the updated `remote-storage` doc line.
- Script run against fixtures (path substituted in a scratch copy):
  - file absent → "No remote shares attached" + attach hint;
  - markers present but empty → same message;
  - NFS+gid, CIFS+gid, CIFS without gid → correct protocol/server:export, mountpoint,
    writers line, and credentials *path* (never contents) for CIFS;
  - declared-but-unit-missing → "not applied yet — run: just rebuild";
  - simulated live mount (fake `findmnt`/`df`) → "mounted — 7.2T total, 3.1T used, 4.1T free";
  - simulated active automount unit (fake `systemctl`) → "ready — mounts on first access".
- Status never stat()s the mountpoint, so listing cannot trigger an automount or block on
  an offline NAS; `df` is bounded by `timeout 5`.
- `scripts/preflight.sh` exit 0 (shellcheck stage clean).

## Scores
| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 96% | A |
| Functionality | 96% | A |
| Code Quality | 95% | A |
| Security | 98% | A |
| Performance | 100% | A |
| Consistency | 96% | A |
| Build Success | 100% | A |

**Overall Grade: A (97%)**

## Notes
- Like `detach`, only entries between the managed markers are listed.
- The interactive menu return-to-menu behaviour is the shared `_menu` "stay" path (already
  used by `feature list`); it was not re-tested here beyond the recipe parsing.
- The new script is not run as a live `just remote-storage list` in the sandbox (needs sudo
  and a real `/etc/nixos/vexos-variant`).
