# L-10 — kernel-install-override timing window: deleted, not restored on failure

Status: Phase 1 (Research & Specification)
Source: MASTER_PLAN L-10 (BUGS L10) · `modules/nix.nix:142-165`
(current file: this logic no longer lives in `modules/nix.nix` at all —
M-26, earlier this session's predecessor work, moved the entire
`vexos-update` shell application to `pkgs/vexos-update/default.nix`
using `writeShellApplication`. The described logic is now at
`pkgs/vexos-update/default.nix:110-147`.)

## Current State

`pkgs/vexos-update/default.nix:121-147`:
```bash
OVERRIDE_FILE="/etc/nixos/kernel-install-override.nix"
if [ -f "$OVERRIDE_FILE" ]; then
  echo "Kernel install override detected — checking if target kernel is now cached..."
  rm "$OVERRIDE_FILE"
  if ! DRY_CHECK=$(nixos-rebuild dry-build --flake git+file:///etc/nixos#"$VARIANT" 2>&1); then
    echo "error: dry-build failed while checking kernel cache status:" >&2
    printf '%s\n' "$DRY_CHECK" >&2
    exit 1
  fi
  STILL_HEAVY=$(... | grep -E "$HEAVY_BUILD_REGEX" || true)
  if [ -n "$STILL_HEAVY" ]; then
    printf '%s\n' ... > "$OVERRIDE_FILE"     # recreate — already correct
    ...
  else
    ...                                      # leave removed — already correct
  fi
fi
```

The override file must be removed *before* the check dry-build runs,
because its own content (`boot.kernelPackages = lib.mkForce
pkgs.linuxPackages;`) forces the safe channel-default kernel — leaving
it in place would make every dry-build show the safe kernel as already
satisfied, never revealing whether the *real* target kernel is now
cached. So the early `rm` itself is correct and necessary, not the bug.

Traced all three exit paths reachable after that `rm`:
1. **`exit 1` at line 128** (the check dry-build itself errors —
   e.g. a transient network failure, an unrelated eval error, anything
   other than "target kernel not cached yet"): the override file has
   already been deleted at line 124 and is **never restored** before
   the script exits. This silently and permanently removes the
   installer's kernel-safety-net for a failure that has nothing to do
   with kernel caching. **This is the real defect.**
2. **`STILL_HEAVY` non-empty branch (lines 133-141):** already
   recreates the file correctly — not a bug.
3. **`STILL_HEAVY` empty branch (line 144-146):** intentionally leaves
   it removed (target is genuinely cached under the pins the check
   just tested against) — not a bug.

Also traced the two *later* exit points in the same script (main
dry-build failure at line 163, and the `HEAVY_BUILDS` classifier's
`exit 2` at line 222) to check whether either of them interacts badly
with whatever the block above already decided: both restore
`flake.lock` from `flake.lock.bak` before exiting, reverting to the
exact pins the override-check block itself tested against — so
whatever that block concluded (recreate vs. leave-removed) remains
consistent with the reverted lock state in both of those paths. Neither
of the later exit points is actually the bug; the plan's "exit-2 path"
framing does not match this script's current control flow (there is no
override-file interaction on the `exit 2` path at all — the file is
already fully resolved, one way or the other, well before flake.lock
is ever touched). This is the same class of stale/imprecise original-
analysis detail this session has repeatedly found and corrected (see
H-02, M-13, M-28, L-05) — the underlying defect the title describes
("deleted... not restored") is real, just reachable via a different
exit path (`exit 1` at line 128) than the title names.

## Problem Definition

If the kernel-cache-status dry-build check fails for any reason
unrelated to kernel caching, the just-deleted
`kernel-install-override.nix` is never restored before the script
exits — silently and permanently losing the installer's kernel
safety-net on an otherwise-unrelated transient failure.

## Proposed Solution

Factor the override file's (fully static, deterministic) content into
a small shell function defined once, and call it both from the
existing `STILL_HEAVY` recreate branch and from a new restore step on
the check-dry-build-failure path — avoiding duplicating the `printf`
content block a second time.

## Implementation Steps

1. `pkgs/vexos-update/default.nix` — define
   `write_kernel_override() { printf '%s\n' ... > "$OVERRIDE_FILE"; }`
   once, immediately after `OVERRIDE_FILE=` is set, using the exact
   existing content from lines 134-141.
2. Replace the `STILL_HEAVY` non-empty branch's inline `printf` block
   with a call to `write_kernel_override`.
3. In the `exit 1` branch (dry-build check itself fails, lines 126-128),
   call `write_kernel_override` before `exit 1`, and adjust the log
   line to say the override was restored.

## Configuration Changes

None — shell-script-only change inside the `writeShellApplication`
package definition; no NixOS module/option changes.

## Risks and Mitigations

- **Risk:** restoring the override on a failure that turns out to be
  permanent (not transient) means future `vexos-update` runs keep
  re-attempting the same check-and-fail cycle indefinitely.
  **Mitigation:** this matches the existing, accepted behavior at every
  other failure point in this same script (main dry-build failure also
  just restores state and exits 1, expecting the operator to
  investigate and re-run) — not a new failure mode, just consistent
  with the rest of the file.
- **Risk:** shell function ordering — `write_kernel_override` must be
  defined before both call sites use it.
  **Mitigation:** define it immediately after `OVERRIDE_FILE=` is set,
  before the `if [ -f "$OVERRIDE_FILE" ]` block that contains both call
  sites.
- **Risk:** `writeShellApplication` runs ShellCheck at build time (this
  is exactly what M-26 added preflight stage `[8/8]` for) — a shell
  function definition must be valid POSIX-ish bash ShellCheck accepts.
  **Mitigation:** verify in Phase 3 by rebuilding
  `pkgs.vexos.vexos-update` (`nix build .#vexos-update` /
  `bash scripts/preflight.sh` stage `[8/8]`).
