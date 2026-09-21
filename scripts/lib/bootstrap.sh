#!/usr/bin/env bash
# =============================================================================
# scripts/lib/bootstrap.sh — common startup for the installer scripts
# (install.sh, stateless-setup.sh, migrate-to-stateless.sh).
#
# Sourced by each script through its inline `_load_lib` stub, never executed.
# The stub — VEXOS_REV resolution plus _load_lib — is the one piece that cannot
# live here, because fetching this file needs VEXOS_REV first.
#
# Provides: colour variables, the shared build-progress UI (lib/progress.sh, with
# plain-output fallbacks) and the shared prompts (lib/prompts.sh).
# Expects: _load_lib, VEXOS_REV and VEXOS_INSTALLER_TITLE from the caller.
# =============================================================================
# shellcheck disable=SC2034  # colour variables are consumed by the calling script

# ---------- Color helpers (only if stdout is a TTY with color support) -------
# The brand colours (VEXOS_TEAL / VEXOS_ORANGE) are defaulted by lib/progress.sh.
if [ -t 1 ] && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  CYAN='\033[0;36m'
  BOLD='\033[1m'
  RESET='\033[0m'
else
  RED='' GREEN='' YELLOW='' CYAN='' BOLD='' RESET=''
fi

# ---------- Shared full-screen build-progress UI ----------------------------
# render_header / center_block / progress_bar / render_progress / run_live_build
# and the brand-logo screen. Cosmetic, so on any load failure fall back to plain
# streaming output rather than stopping the install.
if ! _load_lib progress.sh; then
  echo -e "${YELLOW}Warning: could not load lib/progress.sh — falling back to plain output.${RESET}" >&2
  center_block() { printf '%s\n' "$1"; }
  render_header() { :; }
  render_progress() { echo -e "${CYAN}→ [${2}/${3}]${RESET} ${BOLD}${1}${RESET}"; }
  progress_bar() { :; }
  run_live_build() {
    local t="$1"; shift
    echo -e "${BOLD}${t}${RESET}"
    BUILD_LOG_PATH="$(mktemp "${TMPDIR:-/tmp}/vexos-build.XXXXXX.log")"
    "$@" 2>&1 | tee "$BUILD_LOG_PATH"
    return "${PIPESTATUS[0]}"
  }
fi

# ---------- Shared prompts ---------------------------------------------------
# Not cosmetic: the scripts cannot ask their questions without it.
if ! _load_lib prompts.sh; then
  echo -e "${RED}✗ Could not load lib/prompts.sh (pinned to ${VEXOS_REV}) — aborting.${RESET}" >&2
  exit 1
fi
