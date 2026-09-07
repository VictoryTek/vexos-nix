# shellcheck shell=bash
# =============================================================================
# lib/progress.sh — vexos-nix shared full-screen build-progress UI
# Repository: https://github.com/VictoryTek/vexos-nix
#
# Sourced by scripts/install.sh, scripts/stateless-setup.sh and
# scripts/migrate-to-stateless.sh so all three installers show the identical
# brand-logo + centered progress-bar + rotating-tip screen while a long build
# runs. This file is the single source of truth for that UI — do not re-inline
# copies of these helpers into the installer scripts.
#
# Contract expected from the sourcing script BEFORE it sources this file:
#   • set -euo pipefail is active (inherited; this file does not set it)
#   • colour variables RED GREEN YELLOW CYAN BOLD RESET are defined
#     (empty strings when the terminal has no colour — this file keys off
#      RESET being non-empty to decide whether to emit colour itself)
#   • VEXOS_REV is set to the git commit this run is pinned to (used to fetch
#     the real PNG logo); if unset, the hardcoded ASCII logo is used
#
# Provides:
#   VEXOS_TEAL VEXOS_ORANGE            brand colours (only if not already set)
#   VEXOS_LOGO VEXOS_LOGO_RENDERED     ASCII fallback + best-effort chafa render
#   VEXOS_TIPS[@]                      rotating tip strings
#   center_block <text>               pad every line to the terminal centre
#   render_header                     clear screen, redraw logo + title
#   progress_bar <pct> <width>        block-character bar string
#   render_progress <label> <n> <m>   compact "→ [n/m] label" phase line
#   run_live_build <title> <cmd...>   run <cmd> with the animated progress screen
# =============================================================================

# ---------- Brand colours (only when the caller enabled colour) -------------
if [ -n "${RESET:-}" ]; then
  : "${VEXOS_TEAL:=\033[38;2;20;166;184m}"
  : "${VEXOS_ORANGE:=\033[38;2;232;121;12m}"
else
  VEXOS_TEAL='' VEXOS_ORANGE=''
fi

# ---------- Brand logo + full-screen header ----------------------------------
# Generated once via `toilet -f mono12 "VEXOS"` and hardcoded here — no runtime
# dependency on toilet. render_header clears the screen and redraws the logo so
# every screen looks like a dedicated installer rather than scrolling shell
# output.
VEXOS_LOGO=' ▄▄    ▄▄  ▄▄▄▄▄▄▄▄  ▄▄▄  ▄▄▄    ▄▄▄▄      ▄▄▄▄
 ▀██  ██▀  ██▀▀▀▀▀▀   ██▄▄██    ██▀▀██   ▄█▀▀▀▀█
  ██  ██   ██          ████    ██    ██  ██▄
  ██  ██   ███████      ██     ██    ██   ▀████▄
   ████    ██          ████    ██    ██       ▀██
   ████    ██▄▄▄▄▄▄   ██  ██    ██▄▄██   █▄▄▄▄▄█▀
   ▀▀▀▀    ▀▀▀▀▀▀▀▀  ▀▀▀  ▀▀▀    ▀▀▀▀     ▀▀▀▀▀'

# center_block "$text" — pads every line of $text so the widest line lands in
# the middle of the current terminal width. Pure bash (no gum dependency).
# Strips ANSI escapes only for the width measurement — the printed line keeps
# its colour codes.
center_block() {
  local cols line stripped maxlen=0 pad
  cols=$(tput cols 2>/dev/null || echo 80)
  while IFS= read -r line; do
    stripped="$(printf '%s' "$line" | sed 's/\x1b\[[0-9;]*m//g')"
    (( ${#stripped} > maxlen )) && maxlen=${#stripped}
  done <<< "$1"
  pad=$(( (cols - maxlen) / 2 ))
  (( pad < 0 )) && pad=0
  while IFS= read -r line; do
    printf '%*s%s\n' "$pad" '' "$line"
  done <<< "$1"
}

# render_header — clears the screen and redraws the centered logo + title.
# HEADER_PAD approximates the logo's centering offset (reused by callers that
# indent left-anchored widgets to roughly the same left edge). HEADER_LINES is
# the number of lines just printed, so run_live_build's dyn_row can track the
# logo's real height instead of a hardcoded row number.
render_header() {
  clear 2>/dev/null || true
  local cols; cols=$(tput cols 2>/dev/null || echo 80)
  HEADER_PAD=$(( (cols - 50) / 2 ))
  (( HEADER_PAD < 0 )) && HEADER_PAD=0
  local logo_text
  if [ -n "${VEXOS_LOGO_RENDERED:-}" ]; then
    logo_text="$VEXOS_LOGO_RENDERED"
    echo -e "$(center_block "$logo_text")${RESET}"
  else
    logo_text="$VEXOS_LOGO"
    echo -e "${VEXOS_TEAL}$(center_block "$logo_text")${RESET}"
  fi
  echo -e "${BOLD}${VEXOS_ORANGE}$(center_block "${VEXOS_INSTALLER_TITLE:-VexOS Installer}")${RESET}"
  echo ""
  HEADER_LINES=$(( $(printf '%s\n' "$logo_text" | wc -l) + 2 ))
}

# progress_bar <percent 0-100> <width> — echoes a filled/empty block-character
# bar. tr operates byte-wise and mangles multi-byte UTF-8 fill characters, so
# runs are built with printf's %.0s repeat trick instead; printf runs its
# format at least once even with zero args, so the zero case is guarded.
progress_bar() {
  local pct="$1" width="$2" filled empty bar
  (( pct < 0 )) && pct=0
  (( pct > 100 )) && pct=100
  filled=$(( width * pct / 100 ))
  empty=$(( width - filled ))
  bar=""
  (( filled > 0 )) && bar+="$(printf '█%.0s' $(seq 1 "$filled"))"
  (( empty > 0 )) && bar+="$(printf '░%.0s' $(seq 1 "$empty"))"
  printf '%s' "$bar"
}

# render_progress "<label>" <current> <total> — one compact status line per
# build phase (e.g. "→ [2/4] Refreshing flake inputs..."), not a bar widget.
render_progress() {
  local label="$1" current="$2" total="$3"
  echo ""
  echo -e "${VEXOS_TEAL}→ [${current}/${total}]${RESET} ${BOLD}${label}${RESET}"
}

# ---------- Live build progress screen (logo stays put, only this redraws) ---
VEXOS_TIPS=(
  "Run 'just update' after reboot to pull the latest cached packages"
  "The Up app checks for and applies system updates from the desktop"
  "vexos-nix tracks /etc/nixos in git — 'sudo git -C /etc/nixos log' shows every change"
  "Re-run this installer any time to switch role or GPU variant"
  "Docs and updates: github.com/VictoryTek/vexos-nix"
)

# run_live_build "<title>" <command...> — runs <command...> in the background
# with its real output captured to a temp log (not shown live: nixos-rebuild's
# own output is too voluminous/low-signal to watch line by line), while a
# cursor-addressed progress bar + rotating tip redraw in place below the
# already-drawn logo. Progress is a simple time-based asymptotic curve, since
# there's no reliable step count to grep for. Sets BUILD_LOG_PATH so the caller
# can show the log on failure (the transparency this trades away by not
# streaming output live).
#
# Each frame clears only the 5 lines it's about to rewrite (\033[2K per line)
# instead of \033[J — clearing the whole region every 0.5s visibly flashed on
# real terminals. Cols, the centered title, every tip's centered text, and
# dyn_row are recomputed by recompute_layout(), called once before the loop and
# again only after a confirmed SIGWINCH (terminal resize).
run_live_build() {
  local title="$1"; shift
  local build_log exit_code=0 dyn_row
  local bar_width=40 elapsed pct tip_idx tip_count=${#VEXOS_TIPS[@]}
  local cols bar_pad centered_title i resized=0
  local -a centered_tips=()
  build_log="$(mktemp "${TMPDIR:-/tmp}/vexos-install-build.XXXXXX.log")"
  # shellcheck disable=SC2034  # BUILD_LOG_PATH is this function's output contract
  BUILD_LOG_PATH="$build_log"

  # _truncate_to_width <text> <max> — returns <text> unchanged if it fits, else
  # the first max-1 characters + an ellipsis. redraw_frame clears the tip line
  # with a single \033[2K (one physical row); an untruncated tip wider than the
  # terminal wraps onto a second row that never gets cleared, leaving a stale
  # fragment when a shorter tip rotates in.
  _truncate_to_width() {
    local text="$1" max="$2"
    if (( ${#text} > max )); then
      printf '%s…' "${text:0:$(( max - 1 ))}"
    else
      printf '%s' "$text"
    fi
  }

  recompute_layout() {
    cols=$(tput cols 2>/dev/null || echo 80)
    bar_pad=$(( (cols - bar_width) / 2 ))
    (( bar_pad < 0 )) && bar_pad=0
    centered_title="$(center_block "$title")"
    centered_tips=()
    for i in "${!VEXOS_TIPS[@]}"; do
      centered_tips[i]="$(center_block "$(_truncate_to_width "Tip: ${VEXOS_TIPS[$i]}" $(( cols - 2 )))")"
    done
    dyn_row=$(( ${HEADER_LINES:-9} + 1 ))
  }
  recompute_layout

  sudo -v 2>/dev/null || true  # refresh the sudo timestamp — a backgrounded job
                               # with redirected stdio can't show a password
                               # prompt if it expires mid-build.

  "$@" >"$build_log" 2>&1 &
  local build_pid=$!

  # redraw_frame <percent> <tip-index-or-empty> — <empty> tip index means the
  # final (100% or blank) frame; still draws the title/bar, clears the tip line.
  redraw_frame() {
    local frame_pct="$1" frame_tip="$2"
    printf '\033[%d;1H' "$dyn_row"
    printf '\033[2K%b\n' "${BOLD}${centered_title}${RESET}"
    printf '\033[2K\n'
    printf '\033[2K%*s%b%b%b %s%%\n' "$bar_pad" '' "$VEXOS_TEAL" "$(progress_bar "$frame_pct" "$bar_width")" "$RESET" "$frame_pct"
    printf '\033[2K\n'
    printf '\033[2K%b\n' "${frame_tip:-}"
  }

  trap 'resized=1' WINCH

  printf '\033[?25l'
  local start_epoch=$EPOCHSECONDS
  while kill -0 "$build_pid" 2>/dev/null; do
    if (( resized )); then
      resized=0
      render_header
      recompute_layout
    fi
    elapsed=$(( EPOCHSECONDS - start_epoch ))
    pct=$(( 92 * elapsed / (elapsed + 60) ))
    tip_idx=$(( (elapsed / 6) % tip_count ))
    redraw_frame "$pct" "${centered_tips[$tip_idx]}"
    sleep 0.5
  done
  wait "$build_pid" || exit_code=$?

  if (( exit_code == 0 )); then
    redraw_frame 100 "$(center_block "Full build log: $build_log")"
  else
    printf '\033[%d;1H\033[J' "$dyn_row"  # failing — drop the animation entirely
  fi
  printf '\033[?25h'
  trap - WINCH
  unset -f redraw_frame recompute_layout _truncate_to_width
  return $exit_code
}

# ---------- Real brand logo via chafa (best-effort, falls back to VEXOS_LOGO) -
# Renders the actual files/pixmaps/desktop/vex.png (shield+V icon, "VEX-OS"
# wordmark) as terminal art instead of the generic toilet-font block text
# above. Both chafa itself and the PNG fetch are best-effort: any failure
# (offline, cache unreachable, GitHub unreachable) leaves VEXOS_LOGO_RENDERED
# empty and render_header() falls back to the hardcoded VEXOS_LOGO string.
_progress_render_logo() {
  local chafa="" store png cols
  if command -v chafa >/dev/null 2>&1; then
    chafa="chafa"
  else
    # chafa has separate bin/man outputs, so --print-out-paths on plain "chafa"
    # prints two lines; the ^bin selector pins it to the binary output.
    store="$(nix --extra-experimental-features 'nix-command flakes' \
      build nixpkgs#chafa^bin --no-link --print-out-paths 2>/dev/null || true)"
    [ -n "$store" ] && [ -x "$store/bin/chafa" ] && chafa="$store/bin/chafa"
  fi
  [ -n "$chafa" ] || return 0
  [ -n "${VEXOS_REV:-}" ] || return 0

  png="$(mktemp "${TMPDIR:-/tmp}/vexos-install-logo.XXXXXX.png")"
  if curl -fsSL "https://raw.githubusercontent.com/VictoryTek/vexos-nix/${VEXOS_REV}/files/pixmaps/desktop/vex.png" \
       -o "$png" 2>/dev/null; then
    # Size the render box to the real terminal width (chafa's symbol-mode
    # resolution is bounded by this box). Capped at 60 cols / 14 rows: a taller
    # box renders a logo that gets cropped at the top of the window. On
    # kitty/sixel terminals chafa auto-detects and renders pixel graphics.
    cols=$(tput cols 2>/dev/null || echo 80)
    (( cols > 60 )) && cols=60
    (( cols > 6 )) && cols=$(( cols - 6 ))
    VEXOS_LOGO_RENDERED="$("$chafa" --size="${cols}x14" --animate=off "$png" 2>/dev/null || true)"
  fi
  rm -f "$png"
}
VEXOS_LOGO_RENDERED="${VEXOS_LOGO_RENDERED:-}"
_progress_render_logo
