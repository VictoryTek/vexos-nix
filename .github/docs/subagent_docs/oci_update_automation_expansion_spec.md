# OCI Container Update Automation — Expansion Spec

## Current State Analysis

`.github/workflows/update-container-images-weekly-wednesday.yml` tracks 8 of the ~14
`virtualisation.oci-containers.containers.*` services defined under `modules/server/`:
portainer, stirling-pdf, authelia, nginx-proxy-manager, dozzle, homepage, dockhand,
arcane. Each tracked entry is `file:image-repo:registry:tag-regex`; the workflow diffs
the current pinned tag in the `.nix` file against the newest tag matching the regex on
Docker Hub or ghcr.io, and commits a `sed`-rewritten pin if a newer one is found.

Six OCI-container services exist but are **not** in the tracked list, discovered via
`grep -rn "oci-containers.containers\." modules/server/`:

| Container | File | Current pin | Registry (verified live) |
|---|---|---|---|
| `maintainerr` | `modules/server/arr.nix:102` | `ghcr.io/maintainerr/maintainerr:3.17.1` | ghcr, repo `maintainerr/maintainerr` |
| `joplin-db` | `modules/server/joplin.nix:155` | `postgres:16` | dockerhub, repo `library/postgres` |
| `joplin-server` | `modules/server/joplin.nix:168` | `joplin/server:latest` — **not pinned** | dockerhub, repo `joplin/server` |
| `grimmory-db` | `modules/server/grimmory.nix:172` | `lscr.io/linuxserver/mariadb:11.4.8` | dockerhub, repo `linuxserver/mariadb` (lscr.io mirrors these tags) |
| `grimmory` | `modules/server/grimmory.nix:188` | `grimmory/grimmory:v0.38.2` | dockerhub, repo `grimmory/grimmory` |
| `uptime-kuma` | `modules/server/uptime-kuma.nix:28` | `louislam/uptime-kuma:1` | dockerhub, repo `louislam/uptime-kuma` |

Live registry checks (Docker Hub / ghcr.io APIs, done during research) confirmed real
tag formats:

- `joplin/server`: full three-part releases exist (`3.7.1` latest seen) — safe to pin
  to an explicit version instead of `latest`.
- `library/postgres`: tags are `16`, `16.6`, `16.14`, `16.15`, ... — major-version-only
  float today.
- `louislam/uptime-kuma`: tags are `1`, `1.23.16`, `1.23.17`, ... — same major-only float.
- `linuxserver/mariadb` (via Docker Hub, which mirrors lscr.io tags): plain semver tags
  exist per release branch (`11.4.8`, `11.4.12`, `11.8.8`, ...).
- `grimmory/grimmory`: plain `vX.Y.Z` tags; **current pin `v0.38.2` is three major
  versions behind the newest available tag `v3.3.1`** — confirmed via live Docker Hub
  query, not a typo in the pin.
- `maintainerr/maintainerr` (ghcr): `X.Y.Z` tags confirmed present, consistent with the
  existing pin format.

## Problem Definition

1. Six OCI-container services can silently drift from their pinned image version
   because nothing checks Docker Hub/ghcr for newer tags and rewrites the pin — the
   weekly workflow simply never looks at them.
2. `joplin-server` is pinned to the mutable `latest` tag, which defeats the
   reproducibility goal the rest of the fleet already follows (stated explicitly in the
   workflow's own header comment) and can't be tracked by a tag-diff script at all.
3. Two of the missing services (`joplin-db`/postgres, `uptime-kuma`) use major-version-only
   floating tags (`16`, `1`) rather than full pins, which the existing tag-diff/regex
   logic doesn't have an entry format for yet.
4. `grimmory` is confirmed three major versions stale — the user has explicitly decided
   (2026-08-17) this should auto-bump freely to the newest tag like the rest of the
   fleet, accepting the resulting major-version jump on the next scheduled run rather
   than gating it.

## Proposed Solution

### 1. Pin `joplin-server` to an explicit version

Change `modules/server/joplin.nix:169` from `image = "joplin/server:latest";` to
`image = "joplin/server:3.7.1";` (the newest verified release tag at spec time). This
makes it trackable by the same tag-diff mechanism as every other pinned service and
removes the one truly unpinned image in the fleet.

### 2. Add all six missing services to the `SERVICES` array

Extend the `SERVICES` bash array in
`.github/workflows/update-container-images-weekly-wednesday.yml` with:

```
"modules/server/arr.nix:maintainerr/maintainerr:ghcr:^[0-9]+\.[0-9]+\.[0-9]+\$"
"modules/server/joplin.nix:joplin/server:dockerhub:^[0-9]+\.[0-9]+\.[0-9]+\$"
"modules/server/joplin.nix:postgres:dockerhub:^16\.[0-9]+\$"
"modules/server/grimmory.nix:linuxserver/mariadb:dockerhub:^11\.4\.[0-9]+\$"
"modules/server/grimmory.nix:grimmory/grimmory:dockerhub:^v[0-9]+\.[0-9]+\.[0-9]+\$"
"modules/server/uptime-kuma.nix:louislam/uptime-kuma:dockerhub:^1\.[0-9]+\.[0-9]+\$"
```

**Two script-logic fixes required during implementation, beyond just appending entries**
(both are bugs in the original script that only surface once a file has more than one
tracked image, or a service uses an official/unnamespaced Docker Hub image):

1. `postgres` is an official Docker Hub image — its pull string has no namespace
   (`image = "postgres:16"`), but Docker Hub's API requires the `library/` prefix to
   look it up (`hub.docker.com/v2/repositories/library/postgres/...`). Using
   `library/postgres` as the entry's `repo` field would break the file-matching
   grep/sed, since that substring never appears in `joplin.nix`. Fix: keep the entry's
   `repo` as the literal `postgres` (matches the file), and have `latest_dockerhub_tag`
   auto-prefix `library/` only for the API call, only when the repo has no `/`.
2. The `current=$(grep -oP 'image\s*=\s*"[^"]+:\K[^"]+' "$file")` extraction was
   file-scoped, not repo-scoped — harmless while every tracked file had exactly one
   `image = ...` line, but `joplin.nix` and `grimmory.nix` now each have two. An
   unscoped grep would match both lines and garble `current` into a two-line string,
   breaking both the comparison and the `sed` rewrite for those entries. Fix: scope the
   extraction to the specific repo string (`grep -oP "image\s*=\s*\"[^\"]*${repo}:\K[^\"]+"`)
   so it picks the correct line even in a multi-image file.

Design notes per entry:

- **maintainerr**: same shape as existing ghcr entries (arcane, homepage, dockhand);
  three-part tag, no cap needed.
- **joplin-server**: now pinned (see above), tracked like any other dockerhub
  three-part-tag service.
- **joplin-db (postgres)**: pattern capped to `^16\.[0-9]+$` — tracks minor/patch
  releases within major version 16 only. A postgres major-version bump changes on-disk
  format and requires a manual `pg_upgrade`-style migration; this repo's own comment in
  `joplin.nix` (lines 144-149) already treats the postgres volume as something that must
  not be casually disturbed. The workflow will never propose `postgres:17` under this
  pattern — that stays a deliberate, manual decision.
- **grimmory-db (mariadb)**: pattern capped to `^11\.4\.[0-9]+$` — tracks the same
  `11.4.x` release branch the repo is already on (verified live: `11.4.12` exists on
  Docker Hub today). LinuxServer publishes multiple concurrent major branches
  (`11.4.x`, `11.8.x`); capping avoids an unreviewed cross-branch jump for the same
  migration-risk reason as postgres.
- **grimmory**: uncapped three-part `vX.Y.Z` pattern, per explicit user decision
  (2026-08-17) to let it auto-bump freely. This means the very next scheduled run
  (Wednesday 04:00 UTC) will rewrite the pin from `v0.38.2` straight to whatever is
  newest at that time (`v3.3.1` or later as of this spec) — a real, user-approved
  major-version jump, not an oversight.
- **uptime-kuma**: pattern capped to `^1\.[0-9]+\.[0-9]+$`, same major-lock reasoning as
  postgres, applied consistently even though Uptime Kuma's major-version risk is lower
  — keeps the policy uniform across all floating-major-tag entries in this batch.

### 3. Update the workflow's header comment

The comment at the top of the workflow currently says "Checks the 8 OCI-container
services ... (portainer, homepage, stirling-pdf, authelia, nginx-proxy-manager,
dockhand, dozzle, arcane)". Update it to reflect the new count (14) and list, so the
comment stays accurate documentation rather than stale.

## Implementation Steps

1. Edit `modules/server/joplin.nix`: change `joplin/server:latest` →
   `joplin/server:3.7.1`.
2. Edit `.github/workflows/update-container-images-weekly-wednesday.yml`:
   - Update header comment (service count + list).
   - Append the six new entries to the `SERVICES` array.
3. No other files change. This is not new infrastructure — same script, same
   dockerhub/ghcr helper functions, same commit-back mechanism already in place for the
   existing 8 entries. No new flake inputs, no Context7 lookup needed (no external
   library/dependency involved, pure bash + existing Nix module edits).

## Dependencies

None new. No nixpkgs, flake input, or library changes — this is a CI script edit plus a
one-line image tag change in an existing Nix module.

## Configuration Changes

- `modules/server/joplin.nix`: `joplin-server` image tag `latest` → `3.7.1`.
- `.github/workflows/update-container-images-weekly-wednesday.yml`: `SERVICES` array
  gains 6 entries; header comment updated.

## Risks and Mitigations

| Risk | Mitigation |
|---|---|
| `grimmory` auto-bumps 3 major versions on next Wednesday run, possibly breaking the app or its DB schema | Explicit user decision (2026-08-17) to accept this; no further code mitigation requested. User should watch the first automated grimmory bump and verify the app post-update. |
| Postgres/MariaDB major-version auto-bump could corrupt data or require manual `pg_upgrade`/migration | Regex patterns cap both to their current major (`postgres` → `16.x`, `mariadb` → `11.4.x`), so majors never move without a manual pin edit. |
| `joplin/server:3.7.1` may not actually be the version currently running in production (container was floating on `latest` before this change) | This is a pin-forward, not a downgrade — `latest` always resolved to the newest available tag, and `3.7.1` was the newest verified tag at spec time. Next container recreation will match what `latest` was already serving. Flagging so the user can verify Joplin's own in-app version banner after the next `nixos-rebuild switch` that touches this unit. |
| ghcr.io `/tags/list` has no pagination in the existing helper function, so it may not surface the true newest tag if a repo has >100 tags (observed empirically: `maintainerr/maintainerr` newest visible tag was lower than the already-pinned `3.17.1`) | Pre-existing limitation of the workflow's `latest_ghcr_tag` helper, applies equally to the already-tracked ghcr entries (arcane, homepage, dockhand). Out of scope for this change — not introduced or worsened by it. Worth a future follow-up if it starts causing missed updates. |

## Verification

- `git diff` on both files reviewed for correctness against this spec.
- `nix flake show --impure` — confirm flake structure still evaluates (module edit is a
  string literal change, low risk, but must still pass per Phase 3 rules).
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd` / `-nvidia` / `-vm` — per
  standard Phase 3 gate.
- Since this change touches `modules/server/joplin.nix` (server module), additionally:
  `sudo nixos-rebuild dry-build --flake .#vexos-server-amd` and
  `--flake .#vexos-headless-server-amd`.
- Confirm the new `SERVICES` array entries are syntactically valid bash (array parses,
  no unescaped `$`/`.` issues) — visual review, no CI runner available locally to
  execute the workflow itself.
- Confirm `system.stateVersion` untouched, `hardware-configuration.nix` still not
  tracked (per standard Phase 3 checklist).
