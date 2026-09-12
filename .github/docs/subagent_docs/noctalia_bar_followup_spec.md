# Noctalia bar follow-up — remove media, date in clock, hot-corner swap — spec

## Current state analysis

Follow-up to `noctalia_bar_restyle_spec.md`. Current state in `home/noctalia.nix`:

- `bar.default.end = [ "media" "tray" "network" "bluetooth" "volume" "battery" "session" ]`
  (line ~172) — `media` widget still present.
- `bar.default.center = [ "clock" ]` (line ~171) — no `[widget.clock]` block
  exists, so the clock uses upstream's built-in default format (`{:%H:%M}`,
  time only, no date).
- `hot_corners` (lines 227-239): `top_left = ipc.launcher`,
  `top_right = ipc.controlCenter`, `bottom_left = ipc.overview`
  (`ipc.overview = "noctalia msg window-switcher"`, Noctalia's fullscreen
  dimmed window-grid — its closest equivalent to GNOME's Activities overview,
  per the existing comment at `ipc.overview`'s definition).

## Problem definition / user decisions

1. Remove the `media` widget from the bar entirely.
2. Add the date to the clock widget, single-line compact format
   (e.g. `Thu Sep 11  06:39 PM`), per user's explicit choice over the
   stacked two-line alternative.
3. Swap hot corners so `top_left` (GNOME's conventional Activities corner)
   triggers the window overview, and `bottom_left` gets the launcher instead
   — explicit user decision.

## Research (upstream schema verification)

Verified against pinned `noctalia-shell v5.1.0` source
(`docs/user/bar/widgets/clock.mdx`):

- `[widget.clock]` `format` accepts a Rust/Python-strftime-style token string
  wrapped in `{: ... }`; multiple space-joined tokens on one line are valid
  (e.g. the doc's own vertical example
  `"{:%-I:%M %p}"` for 12-hour clock, matching `shell.time_format = "12h"`
  already set in this file).
- Compact single-line time+date: `"{:%a %b %d  %-I:%M %p}"` — `%a` = short
  weekday (`Thu`), `%b` = short month (`Sep`), `%d` = day-of-month, then two
  spaces, then 12-hour time with AM/PM (`%-I:%M %p`), consistent with the
  existing `time_format = "12h"` setting elsewhere in this file (`shell.time_format`
  governs a different, launcher-only surface — the bar clock's format is
  independent and needs its own explicit `format` string to show 12h + date,
  since upstream's own default is 24h/time-only `{:%H:%M}`).
- `hot_corners` schema (already in use in this file) takes the same
  `{ action = "command"; command = "..."; }` shape per corner — a same-shape
  swap of values needs no new schema lookup.

No Context7 lookup applies (Nix/TOML config edit, no new dependency).

## Proposed solution

Single file edit, `home/noctalia.nix`:

1. `bar.default.end`: drop `"media"` →
   `[ "tray" "network" "bluetooth" "volume" "battery" "session" ]`.
2. Add a `[widget.clock]`-equivalent Nix attrset under `settings.widget.clock`
   (top-level `widget.<id>` table, sibling of `bar`/`theme`/etc., per upstream
   schema) with `format = "{:%a %b %d  %-I:%M %p}"`.
3. `hot_corners`: swap so `top_left = ipc.overview` and
   `bottom_left = ipc.launcher` (values only; `top_right` unchanged).

## Risks and mitigations

- **Risk:** `settings.widget` table doesn't currently exist in
  `home/noctalia.nix` — first use of that top-level key.
  **Mitigation:** `widget.<id>` is documented as a standard top-level TOML
  table in every widget doc page (`[widget.clock]`, `[widget.battery]`, etc.)
  and is independent of `bar.default` — adding it is additive, not a
  restructuring of existing keys.
- **Risk:** clock format typo only WARNs at `noctalia config validate`, not a
  build failure (same caveat as the prior spec).
  **Mitigation:** format string copied from verified upstream doc syntax
  (`docs/user/bar/widgets/clock.mdx`), substituting only the already-used 12h
  token style.
- **Risk:** removing `media` could leave an orphaned reference if `media` is
  used elsewhere (e.g. a keybind or hot corner).
  **Mitigation:** grep confirms `media` only appears in `bar.default.end`, no
  other reference in this file or `files/hypr/hyprland.conf`.

## Implementation steps

1. Edit `home/noctalia.nix`: remove `"media"`, add `widget.clock.format`, swap
   `top_left`/`bottom_left` hot-corner commands.
2. Re-validate: `nix flake show --impure`; `nix eval --impure` toplevel
   drvPath for `vexos-desktop-amd`, `-nvidia`, `-vm` (sudo dry-build
   unavailable in this sandbox, per prior review); `bash scripts/preflight.sh`.
3. Confirm no `stateVersion`/`hardware-configuration.nix`/`flake.nix` drift.
