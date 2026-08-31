# DETACH_REMOTE_STORAGE — Review & QA (Phase 3)

## Scope of change

| File | Change |
|------|--------|
| `scripts/detach-remote-storage.sh` | New. Interactive detacher — parses managed entries, unmounts, rmdir mountpoint, drops orphaned CIFS creds, rewrites `/etc/nixos/storage-remote.nix`. |
| `scripts/attach-remote-storage.sh` | +9 lines: reject a mountpoint already claimed by an existing entry (duplicate `fileSystems` key would be silently collapsed by `listToAttrs`). |
| `justfile` | New `detach-remote-storage` recipe (mirrors `attach-remote-storage`: same group, same `_require-remote-storage-role` guard, same `_run-storage-script` dispatch). One help line in the server-role addendum block. |
| `.github/docs/subagent_docs/DETACH_REMOTE_STORAGE_spec.md` | Phase 1 spec. |

No `.nix` files touched. No `configuration-*.nix`, no `modules/`, no `flake.nix`,
no new flake inputs.

## 1. Specification compliance

| Spec item | Status |
|-----------|--------|
| Interactive numbered menu + "detach ALL" | ✅ step [3/5] |
| Full cleanup: unmount (with `umount -l` fallback), rmdir empty mountpoint, drop orphaned CIFS creds only when no remaining entry uses the same path | ✅ step [4/5] |
| Stop transient automount unit before unmount | ✅ `systemd-escape -p --suffix=automount` |
| `cp -a` backup to `.bak` before rewrite (same as attach) | ✅ step [5/5] |
| Empty result ⇒ valid inert file, offer full deletion | ✅ step [5/5] |
| Never runs `just rebuild` / `nixos-rebuild` — prints reminder only | ✅ |
| Role guard reused | ✅ `_require-remote-storage-role` |
| Sibling attach guard for duplicate mountpoints | ✅ |

## 2. Best practices

- `set -uo pipefail`, same colour/`die`/`ok`/`warn`/`hdr` helpers and house
  style as `attach-remote-storage.sh`.
- Destructive ops are bounded: `rmdir` only (never `rm -rf`), only on an empty
  dir, only on the exact `mountPoint` string parsed from the entry; `rm -f` only
  on the parsed `credentialsFile` path and only when unreferenced by survivors.
- `umount` failure is non-fatal and clearly explained (rebuild drops the unit
  regardless).
- Entry parsing tolerates an unparseable line (skips its live cleanup with a
  warning, keeps it in the file) — no data loss on hand-edited malformed input.

## 3. Consistency with Module Architecture Pattern (Option B)

Not affected — no module or `configuration-*.nix` change. `/etc/nixos/storage-remote.nix`
is host-generated state, explicitly not tracked (`flake.nix:174` pathExists guard,
generated-file header says "do NOT commit"). No new `lib.mkIf`.

## 4. Maintainability

Script is ~190 lines, linear 5-step flow matching the attach script's numbered-step
convention, each block headed by an `hdr` call. `_field` helper centralises entry
parsing. Recipe is a 2-line mirror of the attach recipe.

## 5. Completeness

Covers: single detach, detach-all, not-mounted case, busy-mount case,
non-empty-mountpoint case, shared-credentials case, empty-file case,
absent-file case, malformed-entry case.

Out of scope (documented, not regressions): no argument form (interactive only,
per spec decision); does not touch `storage-pool.nix` (local pools — separate
recipe/owner).

## 6. Performance

N/A — interactive admin script, no hot path. No evaluation impact.

## 7. Security

- No secrets printed. Credentials file is removed, never displayed.
- No new world-writable files; rewritten `storage-remote.nix` inherits perms via
  `cp -a` baseline then `>` truncate-in-place (mode preserved).
- `preflight.sh` CHECK 7 secret scan targets `*.nix` only — not applicable; no
  plaintext secrets introduced in any `.nix` file.
- Root precondition enforced (`id -u` == 0).

## 8. API currency

No external library, no versioned API. Context7 not applicable (confirmed in
spec). Tools used (`umount`, `mountpoint`, `systemd-escape`, `systemctl`, `awk`,
`grep -P`) are all already relied on by `attach-remote-storage.sh` and present on
every NixOS host.

## 9. Build validation

| Check | Result |
|-------|--------|
| `bash -n scripts/detach-remote-storage.sh` | ✅ pass |
| `bash -n scripts/attach-remote-storage.sh` | ✅ pass |
| `shellcheck` (0.11.0) both scripts | ✅ pass, no findings |
| Entry-parsing logic (awk + `_field`) unit-exercised on a 2-entry fixture (cifs + nfs) | ✅ correct fields, nfs `credentialsFile` empty |
| `just --list` shows `detach-remote-storage`; `just --evaluate` | ✅ justfile parses |
| `nix flake show --impure` | ✅ exit 0 (pre-existing unrelated `kernel-override` "not a derivation" warnings only) |
| `sudo nixos-rebuild dry-build` / `nix eval` full closure | ⚠️ **not runnable in this session** — sandbox blocks `sudo` ("no new privileges"), and rootless `nix eval path:/etc/nixos` cannot read `/etc/nixos/secrets` (0700). Deferred to Phase 6 preflight on the user's host / CI. Change is shell/justfile-only with zero Nix-evaluation surface, so closure evaluation is unaffected by construction. |
| `git ls-files hardware-configuration.nix` | ✅ empty |
| `system.stateVersion` in all 6 `configuration-*.nix` | ✅ unchanged (`25.11`), no such file touched |
| New flake inputs | none |

## Score table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 96% | A |
| Functionality | 95% | A |
| Code Quality | 95% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 90% | A- (flake structure + shellcheck pass; full closure dry-build deferred to host/CI — no eval surface in this change) |

**Overall Grade: A (97%)**

## Result

**PASS** — proceed to Phase 6 preflight. The one gap (host dry-build) is an
environment limitation of the review session, not a code issue: the change
contains no Nix code and cannot alter closure evaluation. Preflight on the
user's NixOS host (and CI) exercises the real dry-build.
