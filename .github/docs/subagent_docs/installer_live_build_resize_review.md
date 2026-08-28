# Review — Live-Build Resize/Variable-Height-Logo Fix

## Scope

Single-file change: `scripts/install.sh`. No `.nix` files touched.

## Specification Compliance

Matches `installer_live_build_resize_spec.md`:
- `render_header()` now sets global `HEADER_LINES` (logo line count + 2)
  after printing, mirroring the existing `HEADER_PAD` side-effect pattern.
- `run_live_build()`'s one-time layout computation is factored into a
  nested `recompute_layout()` (cols, bar_pad, centered_title,
  centered_tips, and the previously-hardcoded `dyn_row`, now derived from
  `HEADER_LINES`).
- `trap 'resized=1' WINCH` added; the loop checks the flag once per
  iteration and, only when set, does a full `render_header` +
  `recompute_layout` before continuing with the normal narrow 5-line
  redraw. `trap - WINCH` and `unset -f recompute_layout` added to the
  existing cleanup.

## Best Practices / Consistency

- Steady-state behavior (no resize) is byte-for-byte identical to before —
  same 5-line `\033[2K` redraw, same cadence, no added blink.
- `trap ... WINCH` is scoped correctly: bash traps are process-global, but
  `run_live_build` runs synchronously (blocks on the loop) and always
  clears its own trap (`trap - WINCH`) before returning on every exit path
  (both the success and the `wait`-failure path reach the same trailing
  cleanup), so it cannot leak into any other part of the script.
- `${HEADER_LINES:-9}` fallback preserves the old `dyn_row=10` behavior if
  `render_header` was somehow never called first (defensive, matches spec).

## Correctness notes

- Fixes a genuine regression from the earlier chafa-logo change: the old
  hardcoded `dyn_row=10` was tuned for the fixed 7-line ASCII logo; the
  chafa-rendered logo can be up to 16 lines, which would have made the
  progress bar overlap the logo even with zero resizing involved. Now
  derived from the actual printed header height in both cases.
- Resize recovery triggers on the *next* 0.5s loop tick after the signal,
  not synchronously — acceptable, matches spec (self-healing on repeated
  resizes since the flag is re-checked every iteration).

## Security

No new attack surface — pure local terminal-control logic, no new network
calls, no new external input parsed.

## Build validation

- `bash -n scripts/install.sh` → syntax OK.
- `shellcheck -x scripts/install.sh` (nixpkgs#shellcheck 0.11.0 via WSL) →
  clean on all new/changed lines; only the same pre-existing SC2024
  warning (line 952, unrelated, predates both changes) remains.
- No `.nix` files touched — NixOS dry-build/flake-show steps not
  applicable; `git ls-files hardware-configuration.nix` and
  `system.stateVersion` unaffected by definition.

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 95% | A |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 100% | A |

**Overall Grade: A (99%)**

Functionality docked slightly only because SIGWINCH recovery timing (up to
~0.5s after the resize) can't be visually verified outside a real resizable
terminal session.

## Result: PASS
