# install_center_progress_spec.md

## Problem

Follow-up to `install_branding_takeover_spec.md`. Remaining gaps vs. the
Omarchy screenshots: our screens are left-aligned; Omarchy's read as
centered. Our build phase has no visual progress indicator; Omarchy's final
screen shows a filled progress bar.

## Research: what gum actually supports here

Checked via Context7 (`/charmbracelet/gum`) rather than assuming:

- `gum style --align center --width N` centers **static** text blocks. This
  covers the logo/tagline/fallback menu text fully.
- `gum choose` / `gum input` / `gum confirm` do **not** have a `--align`
  flag — they render left-anchored at the cursor's column. They do support
  `--padding "top right bottom left"` (confirmed against gum's own source,
  `choose/options.go` / `choose/choose.go`: padding wraps the whole composed
  view as a left/right/top/bottom inset). Left-padding can approximate
  centering (indent the widget by N columns) but isn't true reflow-based
  centering — this is a genuine gum limitation, not something skipped.
- gum has no built-in progress-bar widget (only `gum spin`, which is a
  spinner, not a fillable bar). A bar has to be hand-drawn.

## Solution

### 1. Centering

- Compute terminal width once per `render_header` call:
  `COLS="$(tput cols 2>/dev/null || echo 80)"`.
- Add `center_block "$text"`: pure-bash (no gum dependency, works in the
  fallback path too) — finds the longest line in `$text`, computes
  `pad=(COLS-maxlen)/2`, prefixes every line with that many spaces.
- `render_header` centers `VEXOS_LOGO` and the tagline via `center_block`.
- Fallback (`read`-based) menu text blocks (role/server-type/GPU/NVIDIA
  option lists) are also passed through `center_block`, so the no-gum path
  gets the same treatment, not just the gum path.
- `ui_choose`/`ui_confirm`/`ui_input` gain a `--padding "0 0 0 $HEADER_PAD"`
  argument, where `HEADER_PAD` is computed the same way (`(COLS-50)/2`,
  50 = logo width) right after each `render_header` call — approximates
  centering by indenting the widget to roughly the same left edge as the
  centered logo above it. Documented as an approximation, not pixel-perfect
  centering, because gum doesn't expose reflow-based centering for
  interactive widgets.

### 2. Progress bar

No live-redrawing bar: the build phase's existing scrolling output (git
tracking messages, dry-build cache report, live `nixos-rebuild` log) is kept
exactly as-is per the prior spec's explicit decision — a live bar that
redraws in place would either race with that output or require clearing it,
which was already ruled out as a regression.

Instead: a static, non-clearing bar is appended once at the start of each of
the 4 named build phases, showing `n/4` filled — reads as step-by-step
progress through the log, without touching the diagnostic content:

```bash
render_progress() {  # render_progress "<label>" <current> <total>
  local label="$1" current="$2" total="$3"
  local cols; cols=$(tput cols 2>/dev/null || echo 80)
  local bar_width=40
  local filled=$(( bar_width * current / total ))
  local empty=$(( bar_width - filled ))
  local bar; bar="$(printf '%*s' "$filled" '' | tr ' ' '█')$(printf '%*s' "$empty" '' | tr ' ' '░')"
  local pad=$(( (cols - bar_width) / 2 )); (( pad < 0 )) && pad=0
  echo ""
  printf '%*s' "$pad" ''; echo -e "${VEXOS_TEAL}${bar}${RESET}"
  printf '%*s' "$pad" ''; echo -e "${BOLD}[${current}/${total}] ${label}${RESET}"
  echo ""
}
```

Called at 4 points inside the existing build phase, no other lines moved:

1. `render_progress "Preparing system..." 1 4` — right after the "Building
   ${FLAKE_TARGET}..." message, before the UEFI/GRUB preflight block.
2. `render_progress "Refreshing flake inputs..." 2 4` — right before the
   `gum spin`-wrapped flake-update call.
3. `render_progress "Checking build cache..." 3 4` — right before the
   dry-build cache-check call.
4. `render_progress "Building system configuration..." 4 4` — right before
   the final `nixos-rebuild "${REBUILD_ACTION}"` call.

## Implementation Steps

1. Add `center_block()` next to `render_header`.
2. Update `render_header` to center the logo/tagline; compute and export
   `HEADER_PAD` for the `ui_*` helpers to consume.
3. Update `ui_choose`/`ui_confirm`/`ui_input` to pass
   `--padding "0 0 0 ${HEADER_PAD:-0}"`.
4. Wrap each fallback menu's `echo` block in `center_block`.
5. Add `render_progress()`.
6. Insert the 4 `render_progress` calls listed above.
7. No `.nix` changes.

## Risks

- **Risk:** `${#line}` (used for width calc in `center_block`) miscounts
  wide/multibyte characters if the locale isn't UTF-8.
  **Mitigation:** NixOS live ISO defaults to `LANG=C.UTF-8` or similar; the
  logo already relies on UTF-8 rendering (prior spec), so this isn't a new
  assumption — same precondition as the existing brand logo.
- **Risk:** `--padding` on `ui_choose`/`ui_confirm`/`ui_input` could push a
  wide prompt past the terminal's right edge on a narrow terminal.
  **Mitigation:** `HEADER_PAD` is clamped to `>= 0` and derived from actual
  `tput cols`; on a narrow terminal `COLS` is small so `HEADER_PAD` shrinks
  toward 0 automatically (no hardcoded padding).
- **Risk:** intermixing a static progress bar with the scrolling dry-build
  output could look disjointed rather than cohesive.
  **Mitigation:** accepted tradeoff, documented — the alternative (clearing
  between phases) was already rejected in `install_branding_takeover_spec.md`
  for hiding useful diagnostic output; a non-live bar is the compromise that
  keeps both.
