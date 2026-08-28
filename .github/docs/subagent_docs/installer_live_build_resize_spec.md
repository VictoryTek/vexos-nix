# Installer Live-Build Display — Fix Resize Corruption + Variable-Height Logo

## Current state analysis

`run_live_build()` (`scripts/install.sh`, function starting line 169) draws
a header once via `render_header()` (logo + title + blank line), then enters
a `while kill -0 "$build_pid"` loop that redraws only 5 lines every 0.5s
using absolute cursor addressing:

```
local dyn_row=10   # hardcoded
...
printf '\033[%d;1H' "$dyn_row"   # jump to row 10, redraw 5 lines
```

`cols`, `bar_pad`, `centered_title`, and every `centered_tips[]` entry are
computed **once**, before the loop starts, from `tput cols` at that instant.

Two independent defects follow from this:

1. **No `SIGWINCH` handling.** Resizing the terminal window mid-build
   changes the real column count and can reflow already-printed lines in
   the terminal's own buffer, but the script keeps writing at the stale
   `cols`/`bar_pad`/`dyn_row` it computed before the resize. The result is
   exactly what's in the user's screenshot: the title/bar/tip block appears
   duplicated and stacked down the screen, because the cursor-addressed
   writes now land on rows that the terminal has already reflowed content
   into.
2. **`dyn_row=10` is hardcoded**, tuned for the old fixed 7-line
   `VEXOS_LOGO` ASCII-art block (7 logo lines + 1 title line + 1 blank line
   = 9 printed lines ⇒ next free row = 10). The chafa-rendered logo added in
   `installer_logo_chafa_spec.md` can be up to 16 lines tall depending on
   the terminal's aspect-correction, so `dyn_row=10` is now wrong even with
   *no* resize involved — the progress bar can be drawn on top of the logo
   itself.

`render_header()` already exposes one side-effect global for exactly this
kind of reuse (`HEADER_PAD`, consumed by `ui_choose`/`ui_confirm`/`ui_input`
for left-alignment), so extending that pattern is consistent with the
existing code.

## Problem definition

1. Make `dyn_row` correct for whichever logo is actually in use (hardcoded
   ASCII or chafa-rendered), instead of a magic constant.
2. Recover cleanly from a terminal resize during the live-build loop —
   without doing a full-screen clear/redraw on every 0.5s tick (that would
   introduce the "whole terminal blinking" the user explicitly wants to
   avoid). A full redraw should happen only once, right after a resize is
   actually detected.

## Proposed solution architecture

### 1. `render_header()` exposes `HEADER_LINES`

After printing the logo + title + blank line, set a global
`HEADER_LINES` = (number of lines in whichever logo string was printed) + 2
(title line + blank line). This mirrors the existing `HEADER_PAD` global
side-effect already produced by this function.

### 2. `run_live_build()` computes `dyn_row` from `HEADER_LINES`

Replace `local dyn_row=10` with `dyn_row=$(( ${HEADER_LINES:-9} + 1 ))`,
computed inside a new `recompute_layout` helper (see below) rather than as a
one-time local at function entry. `${HEADER_LINES:-9}` keeps the previous
behavior (`dyn_row=10`) as a safety fallback if `render_header` was somehow
never called first.

### 3. Factor the per-run layout computation into `recompute_layout()`

Move the existing one-time computation of `cols`, `bar_pad`,
`centered_title`, `centered_tips[]`, and the new `dyn_row` into a nested
function `recompute_layout()`, called once before the loop starts (same as
today) — no behavior change in the steady state.

### 4. Trap `SIGWINCH`, recover once per resize

Add `trap 'resized=1' WINCH` before the loop. On each loop iteration, check
the flag first:

```
if (( resized )); then
  resized=0
  render_header      # clears screen, redraws logo/title at new size
  recompute_layout    # recomputes cols/bar_pad/centered_*/dyn_row for new size
fi
```

This is the **only** place a full clear happens — normal frames continue to
use the existing narrow 5-line `\033[2K` redraw with no visible flash. A
resize is a real, user-initiated event where a brief redraw is expected
("reset it back to normal"); consecutive frames in between never blink.
`trap - WINCH` and unsetting the new nested function are added to the
existing cleanup at the end of `run_live_build`, alongside the existing
`unset -f redraw_frame`.

## Implementation steps

Single-file change, `scripts/install.sh`:

1. `render_header()` (line 102): after the three `echo`/`echo -e` calls,
   add a `HEADER_LINES=...` assignment (global, no `local`) counting lines
   in whichever logo variable was actually echoed, + 2.
2. `run_live_build()` (line 169): wrap the existing one-time
   `cols`/`bar_pad`/`centered_title`/`centered_tips` computation (currently
   lines ~178-184) in a `recompute_layout()` nested function, add the
   `dyn_row` computation to it, call it once before `sudo -v`.
3. Add `local resized=0; trap 'resized=1' WINCH` before the `while` loop.
4. At the top of the `while` loop body, check `resized` and call
   `render_header` + `recompute_layout` when set.
5. At function end, add `trap - WINCH` and `unset -f recompute_layout`
   alongside the existing `unset -f redraw_frame`.

No other call sites change.

## Dependencies

None new — pure bash (`trap`, nested functions), matching the rest of the
file's dependency-free control flow. Not applicable to Context7.

## Configuration changes

None. No `.nix` files touched.

## Risks and mitigations

- **Resize during the brief window between the `resized` check and
  `redraw_frame`:** a second resize would simply be caught on the *next*
  iteration (0.5s later) — self-healing, no special handling needed.
- **`trap ... WINCH` inside a function:** bash traps set inside a function
  are process-global (not function-scoped), but `run_live_build` is only
  ever active once at a time (it blocks until the background build exits)
  and explicitly disables the trap (`trap - WINCH`) before returning, so it
  cannot leak into any other part of the script.
- **`HEADER_LINES` unset on first call:** guarded with `${HEADER_LINES:-9}`
  in `run_live_build`, preserving prior hardcoded behavior as a fallback.
