# M-14 — `vexos-update` deletes the flake.lock backup too early

Status: Phase 1 (Research & Specification)
Source: MASTER_PLAN M-14 (BUGS M21) · `modules/nix.nix` (`vexos-update` script, read in full)

## Current State

Two related defects in `vexos-update`:

1. **Backup deleted before the step that can still fail.** Line 323
   (`rm -f /etc/nixos/flake.lock.bak`) runs unconditionally right before
   `nixos-rebuild switch` (the step that actually applies the update and can still
   fail — build errors, disk full, activation failures). If `switch` fails after the
   backup is already gone, the user has no way to restore the pre-update `flake.lock`
   via the mechanism this same script set up for exactly that purpose.
2. **Both `nixos-rebuild dry-build` calls swallow their own exit status via `|| true`**
   (lines 222 and 251-252). `dry-build` exits non-zero only on a genuine
   evaluation/build-plan failure — listing packages that need building is a normal,
   zero-exit outcome. `|| true` means a real failure (bad config, syntax error,
   assertion failure) is silently treated as ordinary dry-build output, the
   "will be built:" parser finds nothing to match, and the script proceeds straight to
   `nixos-rebuild switch` as if everything were fine.

## Problem Definition

Make `vexos-update` fail safely and visibly when something is genuinely wrong, instead
of silently discarding the one thing (the lock backup) that would let a user recover,
and instead of silently proceeding into `switch` on top of a masked evaluation failure.

## Proposed Solution

1. Move `rm -f /etc/nixos/flake.lock.bak` to run *after* `nixos-rebuild switch`
   succeeds. Since the whole script runs under `set -euo pipefail`, if `switch` fails
   the script aborts immediately and that line is simply never reached — the backup
   survives on disk.
2. Both dry-build call sites: capture the command's own exit status (via
   `if ! VAR=$(cmd 2>&1); then ...`, which captures output regardless of exit status
   while still allowing the `if` to react to failure — the same pattern already used
   for `vexos-notify`'s `register()` helper). On failure:
   - Kernel-override check (before `flake.lock` has been touched): print the dry-build
     output and exit 1 — nothing to restore yet.
   - Main build classifier (after `flake update` has already run): print the output,
     restore `flake.lock` from the backup, remove the backup, and exit 1 — mirrors
     exactly what the existing "heavy build" block already does for its own reason.

## Implementation Steps

1. `modules/nix.nix` — apply all three changes above within the `vexos-update` script
   body.

## Configuration Changes

None.

## Risks and Mitigations

- **Verify the backup-timing fix actually works under `set -e`** — confirmed by
  tracing that `nixos-rebuild switch`'s failure exit code, under `set -euo pipefail`
  with no `||`/`if` guard around it, aborts the script before reaching the following
  `rm -f` line; this is standard bash `set -e` semantics, not something that needs a
  runtime test in this sandbox (no real target host to run an actual failing
  `nixos-rebuild switch` against).
- **Dry-build failure detection**: verified the `if ! VAR=$(cmd); then` pattern
  correctly captures output in both branches via a standalone bash test (mirroring how
  `register()`'s pattern was verified during the H-17 work this session).
