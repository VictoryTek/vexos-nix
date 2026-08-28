# Installer Live-Build Tip Line — Fix Wrapped-Text Residue

## Current state analysis

`run_live_build()`'s `redraw_frame()` clears and redraws exactly 5 fixed
terminal rows per 0.5s tick (title, blank, bar, blank, tip), each cleared
with a single `\033[2K` before being reprinted. This assumes every one of
those 5 logical lines occupies exactly one physical terminal row.

`VEXOS_TIPS` (line 153) contains strings of very different lengths, e.g.:
- `"Docs and updates: github.com/VictoryTek/vexos-nix"` (~51 chars)
- `"vexos-nix tracks /etc/nixos in git — 'sudo git -C /etc/nixos log' shows every change"` (~87 chars)

Once prefixed with `"Tip: "` and centered, the longest tip can exceed the
terminal's actual column width and wrap onto a second physical row (the
terminal does this automatically; `center_block()` has no width-fitting
logic, it only pads a single logical line for centering). `redraw_frame()`
only issues one `\033[2K` for the tip's *logical* line, so a wrapped second
physical row is never cleared. When the next (shorter) tip rotates in and
doesn't wrap, the previous tip's wrapped remnant is left on screen below
it — exactly the "every change" residue reported by the user.

## Problem definition

Guarantee the tip line never wraps to a second physical row, so the
existing single-`\033[2K`-per-logical-line clearing in `redraw_frame()`
stays correct for every tip, on every terminal width.

## Proposed solution architecture

Truncate each tip (after the `"Tip: "` prefix is added) to fit within the
terminal's actual column width, with a trailing `…` if truncation
happened, computed in `recompute_layout()` — the same function already
responsible for recomputing `cols`-dependent values, and already re-invoked
on `SIGWINCH` (terminal resize) per `installer_live_build_resize_spec.md`,
so a resize also recomputes the truncation width correctly.

Rejected alternative: reserve extra cleared lines below the tip instead of
truncating. Rejected because the "how many lines might this tip wrap into"
calculation would have to be redone per-tip per-resize anyway (no simpler
than truncating), and it leaves a variable-height blank gap depending on
which tip happens to be showing — worse UX than a clean single line.

## Implementation steps

Single-file change, `scripts/install.sh`, inside `run_live_build()`:

1. Add a small `_truncate_to_width <text> <max>` helper (nested function,
   alongside `recompute_layout`/`redraw_frame`): if `${#text} > max`,
   return the first `max-1` characters + `…`; else return `text`
   unmodified.
2. In `recompute_layout()`'s tip-building loop, truncate
   `"Tip: ${VEXOS_TIPS[$i]}"` to `cols - 2` characters before centering.
3. `unset -f _truncate_to_width` alongside the existing
   `unset -f redraw_frame recompute_layout` cleanup at function end.

## Dependencies

None. Pure bash string length (`${#text}`)/substring
(`${text:0:N}`) built-ins. Not applicable to Context7.

## Configuration changes

None. No `.nix` files touched.

## Risks and mitigations

- **Multi-byte characters in tip text** (the em dash `—` in tip #3):
  bash's `${#text}`/`${text:0:N}` operate on characters, not bytes, under a
  UTF-8 locale (the standard NixOS locale), so length/truncation stay
  correct. Worst case on a non-UTF-8 locale is a slightly-off truncation
  point — cosmetic only, not a functional regression versus today.
- **Truncation loses tip content on narrow terminals:** acceptable
  trade-off explicitly chosen over the alternative (see above); the tips
  are non-essential flavor text during a build wait, not required reading.
