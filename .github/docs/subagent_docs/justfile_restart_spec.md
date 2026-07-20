# justfile_restart — Spec

## Current State Analysis

- `justfile:1555` — `status service: _require-server-role` maps a service name to
  one or more systemd unit(s) and optional HTTP check URL(s) via a `case`
  statement (`justfile:1570-1633`), then loops over `UNITS` running
  `systemctl status <unit>.service` for each, followed by HTTP reachability
  checks.
- `justfile:1135` — `_server_service_names` is the single canonical
  space-separated list of valid service names, already shared/reused for
  input validation across `status`, `enable`, `disable`.
- The service → unit(s) mapping (the `case` block inside `status`) exists
  only in `status` today. Multi-unit stacks exist (e.g. `joplin` →
  `docker-joplin-server docker-joplin-db`; `arr` → 6 units; `grimmory` → 2
  units), so restarting a service correctly means restarting all of its
  units, not just one.
- Today, recovering a failed multi-unit stack (as hit in this session with
  Joplin after `network joplin-net not found`) requires the user to
  hand-type unit names and know to `systemctl reset-failed` units that hit
  `start-limit-hit` before restarting — there's no `just` recipe for it.

## Problem Definition

The user wants a `just restart <service>` recipe (or similar), analogous to
the existing `just status <service>`, so recovering a failed or misbehaving
service doesn't require manually looking up systemd unit names or typing
raw `systemctl`/`sudo` commands.

## Proposed Solution

1. Extract the existing service → unit(s) `case` statement out of `status`
   into a new private recipe, `_service-units service`, which just echoes
   the space-separated `UNITS` for a given service name. This is reused
   verbatim — not modified — from `status`'s current case body, so there is
   no behavior change to `status` other than sourcing the same mapping
   through one shared place instead of an inline copy. This avoids having
   two ~45-entry unit-mapping tables that can silently drift out of sync,
   which would otherwise make `restart` map a service to the wrong (or
   missing) systemd unit.
2. Update `status` to call `UNITS=$(just _service-units "$SERVICE")` instead
   of duplicating the case statement inline.
3. Add a new public recipe:
   ```
   [group('Server Services')]
   restart service: _require-server-role
   ```
   Behavior:
   - Validate `service` against `_server_service_names` (same pattern as
     `status`/`enable`/`disable`).
   - Resolve `UNITS` via `just _service-units "$SERVICE"`.
   - Run `sudo systemctl reset-failed $UNITS` (ignore failure — units that
     aren't in a failed state simply no-op) so a unit that previously hit
     `start-limit-hit` (as `docker-joplin-db.service` did in this session)
     can actually restart instead of refusing to start again.
   - Run `sudo systemctl restart $UNITS` as a **single** `systemctl`
     invocation (not a per-unit loop). Passing multiple unit names to one
     `systemctl restart` call lets systemd resolve `After=`/`Requires=`
     ordering between them as one transaction — this matters for stacks
     like `joplin` where `docker-joplin-db` must come up before
     `docker-joplin-server` (declared via `dependsOn` in
     `modules/server/joplin.nix`, which generates `After=`/`Requires=` on
     the generated systemd units per `modules/server/joplin.nix:185-188`).
     A naive per-unit loop would not guarantee this ordering.
   - Print resulting `systemctl status --no-pager --lines=5` for each unit
     afterward so the user immediately sees whether the restart succeeded,
     mirroring the existing `status` recipe's presentation style.

## Implementation Steps

1. Add `_service-units service` private recipe in `justfile`, placed
   immediately before `status` (same file region, `Server Services` group
   area), containing the case statement moved (not duplicated) from
   `status`.
2. Modify `status` to call the new private recipe for `UNITS` resolution.
3. Add `restart service: _require-server-role` recipe, placed immediately
   after `status`, implementing the behavior above.

## Dependencies

None — no new packages, no new flake inputs. Pure `justfile`/bash change.

## Configuration Changes

None. No NixOS module or `configuration-*.nix` file touched;
`system.stateVersion` unaffected.

## Risks and Mitigations

- **Risk:** Extracting the case statement into a shared recipe could
  introduce a typo/formatting break if not copied exactly.
  **Mitigation:** Move the block verbatim (same entries, same syntax); diff
  the two versions before considering the extraction complete.
- **Risk:** `systemctl restart` on a large multi-unit service (e.g. `arr`,
  6 units) could take longer or restart something the user didn't intend
  if the mapping is stale.
  **Mitigation:** Same mapping already trusted by `status` today — no new
  risk introduced beyond what already exists for `status`'s HTTP checks.
- **Risk:** `reset-failed` could mask a persistent underlying failure by
  clearing the failed state without fixing the root cause.
  **Mitigation:** Acceptable — `restart` is an explicit user action meant to
  retry after they believe the underlying issue is fixed (e.g. after a
  config change or manual intervention); if the unit fails again,
  `systemctl restart`'s own exit code and the printed `systemctl status`
  output surface that immediately.
