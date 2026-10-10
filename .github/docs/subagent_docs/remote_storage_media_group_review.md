# remote_storage_media_group — Review

Result: **PASS** (no refinement cycle needed)

## Spec compliance
All five spec items implemented as written. One deliberate scoping call:
prowlarr is not touched (upstream `DynamicUser = true`, no static user, never
touches the media tree). Docker-based media modules already take PUID/PGID.

## Validation
- `nix flake show --impure` — 30 configs.
- drvPath eval, one per role: desktop, stateless, server*, headless-server*, htpc, vanilla.
  (*server roles need the CI `networking.hostId` override — pre-existing assertion.)
- `nix build --dry-run` (path: ref, no sudo in sandbox): desktop-amd/nvidia/vm, htpc-amd,
  stateless-amd, vanilla-amd; server-amd and headless-server-amd with arr+plex+jellyfin+
  audiobookshelf enabled and a cifs+gid remote.
- Scenario evals (server-amd, all media services on):
  - no remote → every service user `extraGroups = []`, no `media` group;
  - cifs+gid(+uid) → `gid=/file_mode=0664/dir_mode=0775/uid=` in options, `media.gid=3000`,
    all nine service users `["media"]`;
  - nfs+gid → NFS options unchanged, group + memberships present;
  - cifs without gid → options byte-identical to before;
  - mixed gids → module assertion fires with a clear message.
- Script step 5 exercised in a harness: non-numeric rejected, blank skips, mismatch with
  existing gid rejected, gid already used by a different local group rejected.
- `scripts/preflight.sh` exit 0 (shellcheck clean). Formatting WARN is repo-wide, pre-existing.
- `hardware-configuration.nix` untracked; `system.stateVersion` untouched.

## Scores
| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 95% | A |
| Functionality | 97% | A |
| Code Quality | 95% | A |
| Security | 98% | A |
| Performance | 100% | A |
| Consistency | 95% | A |
| Build Success | 100% | A |

**Overall Grade: A (97%)**

## Notes for the user
- `uid` only takes effect together with `gid` (per request).
- An explicit per-mount `options = [...]` override still replaces all defaults, so
  `gid` then only creates the group; the override must carry its own ownership options.
