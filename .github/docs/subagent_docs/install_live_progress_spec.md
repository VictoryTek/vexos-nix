# install_live_progress_spec.md

## What Omarchy actually does (traced to source this time)

Found the real mechanism in `basecamp/omarchy`'s `bin/omarchy-provision-owner`
(the first-boot/ISO setup screen the user's screenshots are from — not the
`install/` directory investigated previously, which only covers post-boot
package config). It is plain bash + `gum` + raw ANSI cursor addressing —
no compiled TUI:

- `render_setup_static()`: hides the cursor, does ONE full clear, draws the
  logo at a vertically-centered row.
- `render_setup_dynamic()`: runs in a loop (not a full clear) — moves the
  cursor to a fixed row below the logo (`CSI row;1H`), reprints just the
  title/bar/tip block, then `CSI J` (clear-to-end) to wipe any leftover
  stale characters below. The logo above is never touched again.
- `progress_bar()`: hand-rolled `█`/`░` fill, no gum widget.
- Progress is a blend of real signal (`grep -c 'Completed:' "$LOG_FILE"`
  against a known total step count) and a time-based asymptotic floor
  (`floor = lo + (span-1)*t/(t+tau)`) so the bar always creeps forward even
  during a phase with no discrete steps to count — it never looks stuck, and
  never overstates progress either.
- Tips rotate every 8s based on elapsed wall time, centered under the bar.
- Centering (`center`, `left_padding`) is computed fresh every redraw from
  `stty size`, not cached — correct even if the console resizes mid-install.

This is directly portable to `scripts/install.sh` using the same techniques
already in the file (bash, ANSI codes) — no new dependency.

## Where this applies here

vexos-nix's build phase already has a step Omarchy doesn't: the pre-build
dry-build cache report (which packages will be fetched vs. built locally).
That stays exactly as-is — short, reviewed once, valuable. The literal
`nixos-rebuild "${REBUILD_ACTION}"` invocation is the long, verbose,
low-signal-per-line step (this is the actual analog of Omarchy's
"installation show" — it runs right before reboot, after all questions are
answered). That's the one getting the live progress screen.

**Trade-off vs. hiding the log entirely (accepted deliberately):** Omarchy
throws its package-manager output away except into a log file, trusting
`pacman`'s error surfacing. `nixos-rebuild`'s own errors are exactly what
the existing failure branch tells the user to "review the output above" for
— so hiding them behind a bar would be a real regression. Compromise: the
live build's real stdout/stderr is redirected to a temp log file while the
bar animates; on failure, the last part of that log is printed immediately
(so the error is still visible right away, not just "check the log");
on success, the log path is mentioned so it stays available on request.

## Implementation

```bash
run_live_build() {  # run_live_build "<title>" <command...>
  local title="$1"; shift
  local build_log start_now elapsed pct bar_width=40 tip_idx tip_count=${#VEXOS_TIPS[@]}
  local exit_code=0 dyn_row=10

  build_log="$(mktemp /tmp/vexos-install-build.XXXXXX.log)"
  sudo -v   # refresh the sudo timestamp before backgrounding — a background
            # job with redirected stdio can't show a password prompt.

  "$@" >"$build_log" 2>&1 &
  local build_pid=$!

  printf '\033[?25l'
  local start_epoch=$EPOCHSECONDS
  while kill -0 "$build_pid" 2>/dev/null; do
    elapsed=$(( EPOCHSECONDS - start_epoch ))
    pct=$(( 92 * elapsed / (elapsed + 60) ))   # asymptotic, never hits 100 on its own
    tip_idx=$(( (elapsed / 6) % tip_count ))
    printf '\033[%d;1H\033[J' "$dyn_row"
    echo -e "${BOLD}$(center_block "$title")${RESET}"
    echo ""
    printf '%*s' "$(( ($(tput cols 2>/dev/null || echo 80) - bar_width) / 2 ))" ''
    echo -e "${VEXOS_TEAL}$(progress_bar "$pct" "$bar_width")${RESET} ${pct}%"
    echo ""
    echo -e "$(center_block "Tip: ${VEXOS_TIPS[$tip_idx]}")"
    sleep 0.5
  done
  wait "$build_pid" || exit_code=$?

  printf '\033[%d;1H\033[J' "$dyn_row"
  if (( exit_code == 0 )); then
    echo -e "${BOLD}$(center_block "$title")${RESET}"
    echo ""
    printf '%*s' "$(( ($(tput cols 2>/dev/null || echo 80) - bar_width) / 2 ))" ''
    echo -e "${VEXOS_TEAL}$(progress_bar 100 "$bar_width")${RESET} 100%"
    echo ""
    echo -e "$(center_block "Full build log: $build_log")"
  fi
  printf '\033[?25h'
  BUILD_LOG_PATH="$build_log"
  return $exit_code
}

progress_bar() {  # progress_bar <percent> <width>
  local pct="$1" width="$2" filled empty bar
  (( pct < 0 )) && pct=0; (( pct > 100 )) && pct=100
  filled=$(( width * pct / 100 )); empty=$(( width - filled ))
  bar=""
  (( filled > 0 )) && bar+="$(printf '█%.0s' $(seq 1 "$filled"))"
  (( empty > 0 )) && bar+="$(printf '░%.0s' $(seq 1 "$empty"))"
  printf '%s' "$bar"
}

VEXOS_TIPS=(
  "Run 'just update' after reboot to pull the latest cached packages"
  "The Up app checks for and applies system updates from the desktop"
  "vexos-nix tracks /etc/nixos in git — 'sudo git -C /etc/nixos log' shows every change"
  "Re-run this installer any time to switch role or GPU variant"
  "Docs and updates: github.com/VictoryTek/vexos-nix"
)
```

Replaces:
```bash
if sudo nixos-rebuild "${REBUILD_ACTION}" --flake "git+file:///etc/nixos#${FLAKE_TARGET}"; then
```
with:
```bash
if run_live_build "Building ${FLAKE_TARGET}..." \
     sudo nixos-rebuild "${REBUILD_ACTION}" --flake "git+file:///etc/nixos#${FLAKE_TARGET}"; then
```

Failure branch gains one line before the existing "Review the output above"
message: `tail -n 60 "$BUILD_LOG_PATH"` (real output is no longer "above" on
screen since it went to the log, so it must be printed explicitly — this is
the one place the trade-off above is paid back).

The 3 existing static `render_progress` calls (Preparing/Refreshing/Checking
cache — phases 1-3/4) are unaffected; only phase 4/4 (the actual rebuild)
gets converted from `render_progress` + plain `if sudo nixos-rebuild...` to
`run_live_build`.

## Risks

- **`sudo -v` timing:** refreshes the cached credential right before
  backgrounding; if the user's sudoers timeout is unusually short (not
  vexos-nix's default) it could still expire mid-build — same exposure the
  script already has for the multi-minute dry-build step today, not a new
  risk introduced here.
- **Terminal without cursor-addressing support:** `\033[row;1H` is standard
  ANSI/VT100, same capability level `clear` (already used) requires — no new
  terminal floor.
- **Losing the live log on failure:** mitigated by `tail -n 60` printed
  immediately in the failure branch, plus the full path kept in
  `$BUILD_LOG_PATH` (not deleted) so nothing is lost vs. today's behavior.
- **`EPOCHSECONDS`:** bash 5+ builtin. NixOS live ISO ships current bash; if
  ever absent, `elapsed` would error — acceptable given the whole script
  already assumes bash 4+ (`${var,,}` is used throughout).
