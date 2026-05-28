# Universal Update Path Plan

## Objective
Create one universal update workflow for every host and role:
- Primary command remains `just update` (and Up uses the same backend).
- No long local source builds on normal hosts.
- No permanent hold loops from expected tiny local derivations.
- Strict blocking remains for unknown or heavy misses.

## Scope
This plan covers:
1. Package structure conventions for PIA-related artifacts.
2. Module changes required to stabilize update behavior.
3. Updater miss-class policy in `vexos-update`.
4. Rollback strategy at runtime and repository level.

This plan does not include writing full PIA-from-source packaging.

## Design Principles
- Single operator workflow across all roles.
- Predictable, deterministic classification of cache misses.
- Conservative default: block unknown misses.
- Safe fallbacks with clear user messaging.

## Exact Implementation Steps

### Phase 1: Define Miss Classification Policy
Files to edit:
- `modules/nix.nix`

Changes:
1. Keep current derivation extraction in `SOURCE_BUILDS`.
2. Add three explicit classes in script logic:
   - `ALWAYS_LOCAL_REGEX`: derivations that are always local NixOS assembly and should never block.
   - `KNOWN_SMALL_LOCAL_REGEX`: known tiny local artifacts (starting with PIA helper derivations) that should not block.
   - `BLOCKING_DERIVATIONS`: everything else.
3. Classification algorithm:
   - Parse all candidates.
   - Drop matches from `ALWAYS_LOCAL_REGEX`.
   - Partition remaining entries into `KNOWN_SMALL_LOCAL` vs `BLOCKING_DERIVATIONS`.
4. Decision logic:
   - If `BLOCKING_DERIVATIONS` is non-empty: restore lock, exit 2, print blocking list.
   - If only `KNOWN_SMALL_LOCAL` remains: continue update and print informational notice.

Initial known-small allowlist patterns:
- `^pia-client\\.drv$`
- `^pia-client\\.desktop\\.drv$`
- `^piactl\\.drv$`

### Phase 2: Add Strict Override Guardrail
Files to edit:
- `modules/nix.nix`

Changes:
1. Add optional strict mode env flag in updater script:
   - `VEXOS_UPDATE_STRICT=1` means no small-local exceptions are allowed.
2. Strict mode behavior:
   - Any post-filter derivation becomes blocking.
3. Keep default mode as policy mode (allow known small local artifacts).

### Phase 3: Align User Entry Points
Files to edit:
- `justfile`
- `README.md`

Changes:
1. In `justfile` comments/help text:
   - Document that `update` uses miss classification.
   - Document that small known local artifacts may proceed.
2. In `README.md` update section:
   - Prefer `just update` / Up as canonical path.
   - Move raw `nix flake update && nixos-rebuild switch` to advanced/manual troubleshooting notes.

### Phase 4: Improve Updater Output Protocol
Files to edit:
- `modules/nix.nix`

Changes:
1. Add two message channels:
   - `VEXOS_CACHE_BLOCK:` for hard blockers.
   - `VEXOS_CACHE_LOCAL_OK:` for non-blocking known local derivations.
2. Keep legacy `VEXOS_CACHE_MISS:` support for backward compatibility if needed.
3. Ensure wording states whether system was changed or not.

### Phase 5: Validation Gates
Commands:
1. `nix flake show`
2. `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd`
3. `sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia`
4. `sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm`
5. `bash scripts/preflight.sh`

Acceptance criteria:
- Unknown/heavy misses still trigger hold with lock restoration.
- Known small PIA helper derivations do not trigger hold.
- One universal operator command remains valid across roles.

## Miss-Class Policy (Final)

### Class A: Always Local (Never Block)
Examples:
- `system-path.drv`
- `etc*.drv`
- `home-manager-*.drv`
- restart-trigger and activation/unit glue derivations

Action:
- Ignore for hold logic.

### Class B: Known Small Local (Allow, Warn)
Examples:
- `pia-client.drv`
- `pia-client.desktop.drv`
- `piactl.drv`

Action:
- Proceed with update.
- Emit `VEXOS_CACHE_LOCAL_OK` lines.

### Class C: Blocking (Hold)
Examples:
- Unrecognized derivations not in class A/B.
- Any large package compile candidate.

Action:
- Restore lock.
- Exit 2.
- Emit `VEXOS_CACHE_BLOCK` lines.

## Rollback Strategy

### Runtime Rollback (Host)
Use when an applied update has runtime issues:
1. `sudo nixos-rebuild switch --rollback`
2. Confirm active generation:
   - `nixos-rebuild list-generations | tail -5`

### Update Hold Rollback (Automatic)
If blocking misses are detected:
1. `vexos-update` restores `/etc/nixos/flake.lock` from backup.
2. Exits non-zero with explicit blocker list.
3. Leaves current system unchanged.

### Repository Rollback
Use when policy changes regress behavior:
1. Revert relevant commit(s).
2. Run:
   - `nix flake show`
   - required dry-build checks
3. Re-deploy with `just rebuild` on affected hosts.

## Risk Register
1. Over-broad allowlist may permit unintended local builds.
- Mitigation: exact-name patterns only for class B.
2. False blockers from parser drift.
- Mitigation: preserve raw dry-build output in logs for debugging.
3. Operator confusion during transition.
- Mitigation: concise README + Up messages that state block vs allowed-local.

## Deliverables Checklist
- [ ] `modules/nix.nix` miss-class engine implemented.
- [ ] Strict override env flag implemented.
- [ ] `justfile` help/comments aligned.
- [ ] `README.md` update flow aligned.
- [ ] Validation gates passed.
- [ ] Rollback procedure verified.
