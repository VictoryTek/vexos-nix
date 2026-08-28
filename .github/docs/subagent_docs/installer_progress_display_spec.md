# Installer Progress Display — Single-Line Phase Status Instead of Stacked Bars

## Current state analysis

`render_progress()` (`scripts/install.sh`) drew a centered bar-graphic +
label block, appended via plain `echo` at three call sites during the
"Build & switch" section: `"Preparing system..." 1 4`,
`"Refreshing flake inputs..." 2 4`, `"Checking build cache..." 3 4`. Each
call site is separated by a large amount of other scrolling output the
design intentionally keeps visible — UEFI/bootloader patching messages,
git-init output, flake-update output, dry-build cache report — none of
which is cleared between phases.

Because each `render_progress()` call is a brand-new `echo` block (not a
cursor-addressed in-place redraw), and substantial scrolling output happens
between calls, the terminal ends up with 2-3 separate large bar+label
widgets stacked down the screen over the course of a single install run —
reported by the user as "why does it spawn new progress bars instead of
moving the same one forward."

## Problem definition

Stop stacking full bar-graphic widgets per phase, while preserving the
existing design intent that each phase's own informational output (git
init messages, flake update output, cache report) stays visible as a
scrolling log — not cleared or hidden.

## Considered approaches

1. **True single bar, redrawn in place** (rejected for this pass): would
   require the same class of fixed-row cursor-addressing already used in
   `run_live_build()`, but is structurally incompatible with this section's
   flow — `run_live_build` works because its background job's real output
   is diverted to a log file specifically so nothing else scrolls between
   frames. Here, git-init/flake-update/cache-check output is deliberately
   left on screen between phases, so a fixed on-screen row would routinely
   get scrolled past and out from under a later "redraw at row N," corrupting
   the display (the same failure class just fixed for terminal resize).
   Making this work would mean either diverting all of that phase output to
   a log file (changing what's visible today) or implementing a scrolling
   region — materially more complexity for a status indicator. User asked
   for the simpler option instead.
2. **One compact status line per phase (chosen):** replace the bar+blank+
   label+blank block with a single line, e.g.
   `→ [2/4] Refreshing flake inputs...`. Still prints once per phase
   transition (so the existing "what happened, in order" log semantics are
   unchanged), but there's no more large duplicated bar-graphic widget —
   just a short marker line, consistent in weight with the `✓`/`⚠`/`✗`
   status lines already used everywhere else in this script.

## Implementation steps

Single-file change, `scripts/install.sh`:

1. Simplify `render_progress()` to `echo ""` + one `echo -e` line:
   `${VEXOS_TEAL}→ [${current}/${total}]${RESET} ${BOLD}${label}${RESET}`.
2. Remove the now-unused bar-width/padding/centering logic from
   `render_progress()` (the `progress_bar` helper itself is unchanged and
   still used by `run_live_build()`'s live redraw).
3. No call-site changes — `render_progress "Preparing system..." 1 4` etc.
   keep their existing signature and call sites.

## Dependencies

None. Pure bash. Not applicable to Context7.

## Configuration changes

None. No `.nix` files touched.

## Risks and mitigations

- **Less visual weight than a bar graphic:** intentional — that visual
  weight was the actual complaint (large duplicated widgets). A single
  status line still clearly marks phase transitions.
- **`progress_bar` helper now has one fewer caller:** confirmed still used
  by `run_live_build()`'s `redraw_frame` (line ~219) — not dead code.
