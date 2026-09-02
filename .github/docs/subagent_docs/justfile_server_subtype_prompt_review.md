# justfile: server GUI/headless sub-prompt — Review

## Specification Compliance

Matches spec exactly: role menu in `switch` (justfile:177-219) and `update`
(justfile:744-785) collapsed to remove the standalone `headless-server`
entry; a server-type sub-prompt (wording copied verbatim from
`scripts/install.sh:410-413`) added immediately after role resolution,
firing only inside the `-z "$ROLE"` interactive branch. Non-interactive
positional-arg calls (`just switch headless-server amd`) are untouched —
confirmed by inspection: the sub-prompt block is nested inside the same
`if [ -z "$ROLE" ]; then ... fi` guard that already skipped entirely when a
role is passed as an argument.

## Best Practices / Consistency

Bash style matches surrounding code (same `case`/`while` idiom used
elsewhere in the file for the NVIDIA-branch and desktop-environment
sub-prompts). No new abstractions introduced. `SERVER_TYPE` is a new local
var scoped to the `#!/usr/bin/env bash` recipe block, consistent with
`DESKTOP_ENV`/`VM_PLATFORM` pattern already in `switch`.

## Maintainability / Completeness

Both duplicated menu blocks (`switch` and `update`) were updated in lockstep
so they stay identical, matching the pattern already used for
role/GPU-variant menus across both recipes.

## Security / Performance

No changes to privilege boundaries, file writes, or command execution paths
— pure prompt/branching logic. No performance impact.

## Build Validation

- `nix flake show --impure`: **PASS** — full output enumerated, no errors;
  only pre-existing unrelated warnings (`kernel-override.name is not a
  derivation`, `kernel-overrideDerivation.name is not a derivation`).
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd` /
  `-nvidia` / `-vm`, and the server/headless-server dry-builds: **NOT RUN**
  — `sudo` is unavailable in this sandboxed session
  (`sudo: the "no new privileges" flag is set...`), a container-level
  restriction, not a failure introduced by this change. No `.nix` file was
  touched by this change, so no build/eval-affecting surface exists for
  dry-build to exercise beyond what `nix flake show --impure` already
  covers (module/output enumeration).
- Standalone bash-logic verification (since dry-build was unavailable):
  extracted the exact new `switch` role-selection block (justfile:177-219)
  into a standalone script and ran it under `bash` with piped stdin for all
  four reachable outcomes:
  - `4` then `1` → `ROLE=headless-server` ✓
  - `4` then `2` → `ROLE=server` ✓
  - `server` then `headless` → `ROLE=headless-server` ✓
  - `server` then `gui` → `ROLE=server` ✓
- `git ls-files hardware-configuration.nix`: confirmed empty (unaffected by
  this change; not touched).
- `system.stateVersion`: not touched — no `configuration-*.nix` file was
  edited.
- No new flake inputs added — `follows` check N/A.

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 100% (logic-verified; live dry-build blocked by sandbox) | A |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | N/A — flake structure PASS; dry-build unavailable in this session (environment constraint, not a defect) | — |

**Overall Grade: A (100%), with one caveat: live `nixos-rebuild dry-build`
verification could not be executed in this sandboxed session and is
recommended before the user runs `just switch` for real.**

## Result

**PASS**, conditional on the user (or a follow-up session with sudo access)
running the two Phase 3-mandated dry-builds
(`vexos-server-amd`, `vexos-headless-server-amd`) before relying on this in
production. Given the change is bash-only with no `.nix` diff, risk of a
build regression is assessed as negligible.
