#!/usr/bin/env bash
# =============================================================================
# install.sh — vexos-nix Interactive First-Boot Installer
# Repository: https://github.com/VictoryTek/vexos-nix
#
# Usage (one-liner, recommended):
#   curl -fsSL https://raw.githubusercontent.com/VictoryTek/vexos-nix/main/scripts/install.sh | bash
#
# Or clone first and run locally:
#   bash scripts/install.sh
#
# Supported roles (expand this list as new roles are added to the flake):
#   desktop         — Gaming/workstation (AMD, NVIDIA, Intel, VM)
#   stateless       — Minimal/clean build (no gaming/dev/virt/ASUS modules) (AMD, NVIDIA, Intel, VM)
#   htpc            — Home theatre PC (AMD, NVIDIA, Intel, VM)
#   server          — GUI server / self-hosted services (AMD, NVIDIA, Intel, VM)
#   headless-server — CLI-only server, no desktop environment (AMD, NVIDIA, Intel, VM)
#   vanilla         — Stock NixOS baseline for system restore (AMD, NVIDIA, Intel, VM)
#
# SECURITY NOTICE:
#   This script is fetched from raw.githubusercontent.com and executed directly.
#   Always verify the source URL above before running.
#   Source code: https://github.com/VictoryTek/vexos-nix/blob/main/scripts/install.sh
# =============================================================================

set -euo pipefail

# ---------- Resolve one commit for this entire run ---------------------------
# main is a moving target, and a full install can take several minutes. Without
# this, install.sh handing off to stateless-setup.sh/migrate-to-stateless.sh via
# `curl main/... | bash` could silently mix code from two different commits if
# main is updated mid-run. Resolve the commit once and export it so those
# sub-scripts inherit the same pin instead of re-resolving main themselves.
if [ -z "${VEXOS_REV:-}" ]; then
  if command -v git >/dev/null 2>&1; then
    _REV_GIT="git"
  else
    _REV_GIT="$(nix --extra-experimental-features 'nix-command flakes' \
      build nixpkgs#git --no-link --print-out-paths)/bin/git"
  fi
  VEXOS_REV="$("$_REV_GIT" ls-remote https://github.com/VictoryTek/vexos-nix main | cut -f1)"
fi
export VEXOS_REV

SCRIPT_URL="https://raw.githubusercontent.com/VictoryTek/vexos-nix/${VEXOS_REV}/scripts/install.sh"

# ---------- Color helpers (only if stdout is a TTY with color support) -------
if [ -t 1 ] && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  CYAN='\033[0;36m'
  BOLD='\033[1m'
  RESET='\033[0m'
  # Brand colors sampled from files/pixmaps/*/vex.png (teal wordmark, orange
  # shield accent), brightened slightly for legibility on a terminal background.
  VEXOS_TEAL='\033[38;2;20;166;184m'
  VEXOS_ORANGE='\033[38;2;232;121;12m'
else
  RED='' GREEN='' YELLOW='' CYAN='' BOLD='' RESET='' VEXOS_TEAL='' VEXOS_ORANGE=''
fi

# ---------- Brand logo + full-screen header ----------------------------------
# Generated once via `toilet -f mono12 "VEXOS"` and hardcoded here — no runtime
# dependency on toilet. render_header clears the screen and redraws the logo so
# every prompt screen looks like a dedicated installer rather than scrolling
# shell output (the long-running build/dry-build sections deliberately do NOT
# call this — that output is meant to stay on screen and scroll, not flash away).
VEXOS_LOGO=' ▄▄    ▄▄  ▄▄▄▄▄▄▄▄  ▄▄▄  ▄▄▄    ▄▄▄▄      ▄▄▄▄
 ▀██  ██▀  ██▀▀▀▀▀▀   ██▄▄██    ██▀▀██   ▄█▀▀▀▀█
  ██  ██   ██          ████    ██    ██  ██▄
  ██  ██   ███████      ██     ██    ██   ▀████▄
   ████    ██          ████    ██    ██       ▀██
   ████    ██▄▄▄▄▄▄   ██  ██    ██▄▄██   █▄▄▄▄▄█▀
   ▀▀▀▀    ▀▀▀▀▀▀▀▀  ▀▀▀  ▀▀▀    ▀▀▀▀     ▀▀▀▀▀'

# center_block "$text" — pads every line of $text so the widest line lands in
# the middle of the current terminal width. Pure bash (no gum dependency) so
# the no-gum fallback prompts get the same centering as the gum ones. Strips
# ANSI escapes only for the width measurement (colored lines would otherwise
# measure wider than they render) — the printed line keeps its color codes.
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

# HEADER_PAD approximates the logo's own centering offset, reused by the
# ui_* helpers below to indent gum's (left-anchored) interactive widgets to
# roughly the same left edge as the centered logo/text above them — gum has
# no --align flag for choose/input/confirm, only --padding, so this is an
# approximation, not true reflow-based centering.
render_header() {
  clear 2>/dev/null || true
  local cols; cols=$(tput cols 2>/dev/null || echo 80)
  HEADER_PAD=$(( (cols - 50) / 2 ))
  (( HEADER_PAD < 0 )) && HEADER_PAD=0
  echo -e "${VEXOS_TEAL}$(center_block "$VEXOS_LOGO")${RESET}"
  echo -e "${BOLD}${VEXOS_ORANGE}$(center_block "VexOS Interactive Installer")${RESET}"
  echo ""
}

# render_progress "<label>" <current> <total> — static (non-live-redrawing)
# progress bar snapshot, appended once per build phase. Deliberately not a
# live-updating bar: the build phase's own scrolling output (dry-build cache
# report, live nixos-rebuild log) must stay visible, not be cleared/redrawn.
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

render_progress() {
  local label="$1" current="$2" total="$3"
  local cols bar_width=40 pad
  cols=$(tput cols 2>/dev/null || echo 80)
  pad=$(( (cols - bar_width) / 2 ))
  (( pad < 0 )) && pad=0
  echo ""
  printf '%*s' "$pad" ''; echo -e "${VEXOS_TEAL}$(progress_bar $(( current * 100 / total )) "$bar_width")${RESET}"
  printf '%*s' "$pad" ''; echo -e "${BOLD}[${current}/${total}] ${label}${RESET}"
  echo ""
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
# there's no reliable step count to grep for the way Omarchy counts completed
# pacman-hook scripts. Sets BUILD_LOG_PATH so the caller can show the log on
# failure (the transparency this trades away by not streaming output live).
#
# Each frame clears only the 5 lines it's about to rewrite (\033[2K per line)
# instead of \033[J (clear-to-end-of-screen) — the earlier version cleared the
# whole region below the logo every 0.5s, which visibly flashed/blinked on
# real terminals. Cols, the centered title, and every tip's centered text are
# computed once before the loop (each is a handful of forked subprocesses —
# tput, sed, a read loop) rather than every frame, which was the other source
# of visible lag feeding the flicker.
run_live_build() {
  local title="$1"; shift
  local build_log exit_code=0 dyn_row=10
  local bar_width=40 elapsed pct tip_idx tip_count=${#VEXOS_TIPS[@]}
  local cols bar_pad centered_title i
  local -a centered_tips=()
  build_log="$(mktemp /tmp/vexos-install-build.XXXXXX.log)"
  BUILD_LOG_PATH="$build_log"

  cols=$(tput cols 2>/dev/null || echo 80)
  bar_pad=$(( (cols - bar_width) / 2 ))
  (( bar_pad < 0 )) && bar_pad=0
  centered_title="$(center_block "$title")"
  for i in "${!VEXOS_TIPS[@]}"; do
    centered_tips[i]="$(center_block "Tip: ${VEXOS_TIPS[$i]}")"
  done

  sudo -v  # refresh the sudo timestamp — a backgrounded job with redirected
           # stdio can't show a password prompt if it expires mid-build.

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

  printf '\033[?25l'
  local start_epoch=$EPOCHSECONDS
  while kill -0 "$build_pid" 2>/dev/null; do
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
  unset -f redraw_frame
  return $exit_code
}

# ---------- gum (nice interactive prompts, best-effort) ----------------------
# Fetched at runtime from the nixpkgs binary cache, same pattern as the git
# fallback below. If unavailable (offline, cache unreachable), $GUM stays empty
# and every ui_* helper below falls back to the plain read-based prompt it wraps.
GUM=""
if command -v gum >/dev/null 2>&1; then
  GUM="gum"
else
  _GUM_STORE="$(nix --extra-experimental-features 'nix-command flakes' \
    build nixpkgs#gum --no-link --print-out-paths 2>/dev/null || true)"
  if [ -n "$_GUM_STORE" ] && [ -x "$_GUM_STORE/bin/gum" ]; then
    GUM="$_GUM_STORE/bin/gum"
  fi
fi

# ui_choose "$title" "value1:label1" "value2:label2" ... — prints $title, lets the
# user arrow-key through the labels, echoes the chosen value on stdout.
# --padding indents the widget by $HEADER_PAD to roughly line up with the
# centered logo above it — gum has no --align flag for interactive widgets,
# only --padding, so this approximates centering rather than reflowing it.
ui_choose() {
  local title="$1"; shift
  local values=() labels=()
  local pair
  for pair in "$@"; do
    values+=("${pair%%:*}")
    labels+=("${pair#*:}")
  done
  local chosen
  chosen="$("$GUM" choose --header "$title" --padding "0 0 0 ${HEADER_PAD:-0}" "${labels[@]}" </dev/tty)"
  local i
  for i in "${!labels[@]}"; do
    if [ "${labels[$i]}" = "$chosen" ]; then
      echo "${values[$i]}"
      return 0
    fi
  done
  return 1
}

# ui_confirm "$prompt" — exit status 0 = yes, 1 = no (matches `if ui_confirm ...`).
ui_confirm() {
  "$GUM" confirm --padding "0 0 0 ${HEADER_PAD:-0}" "$1" </dev/tty
}

# ui_input "$prompt" "$placeholder" — echoes the entered text on stdout.
ui_input() {
  "$GUM" input --header "$1" --placeholder "$2" --padding "0 0 0 ${HEADER_PAD:-0}" </dev/tty
}

# ---------- Header -----------------------------------------------------------
render_header
echo -e "${YELLOW}Source: ${SCRIPT_URL}${RESET}"
echo -e "${YELLOW}Verify: https://github.com/VictoryTek/vexos-nix/blob/${VEXOS_REV}/scripts/install.sh${RESET}"
echo ""

# ---------- Role selection ---------------------------------------------------
render_header
ROLE=""
if [ -n "$GUM" ]; then
  ROLE="$(ui_choose "Select your role" \
    "desktop:Desktop  — Full gaming / workstation stack" \
    "stateless:Stateless — Minimal build (no gaming / dev / virt / ASUS)" \
    "htpc:HTPC    — Home theatre PC" \
    "server:Server  — Server (GUI or Headless)" \
    "vanilla:Vanilla  — Stock NixOS baseline (system restore)")"
else
  while [ -z "$ROLE" ]; do
    center_block "Select your role:
  1) Desktop  — Full gaming / workstation stack
  2) Stateless — Minimal build (no gaming / dev / virt / ASUS)
  3) HTPC    — Home theatre PC
  4) Server  — Server (GUI or Headless)
  5) Vanilla  — Stock NixOS baseline (system restore)"
    echo ""
    printf "Enter choice [1-5] or name (desktop / stateless / htpc / server / vanilla): "
    read -r INPUT </dev/tty
    case "${INPUT,,}" in
      1|desktop)  ROLE="desktop"  ;;
      2|stateless) ROLE="stateless" ;;
      3|htpc)     ROLE="htpc"     ;;
      4|server)   ROLE="server"   ;;
      5|vanilla)  ROLE="vanilla"  ;;
      *)
        render_header
        echo -e "${RED}Invalid selection '${INPUT}'. Choose 1-5 or a role name.${RESET}"
        ;;
    esac
  done
fi

# ---------- Server sub-type selection ----------------------------------------
if [ "$ROLE" = "server" ]; then
  render_header
  SERVER_TYPE=""
  if [ -n "$GUM" ]; then
    SERVER_TYPE="$(ui_choose "Select server type" \
      "headless:Headless Server — CLI only, no desktop environment" \
      "gui:GUI Server      — GNOME desktop environment")"
  else
    while [ -z "$SERVER_TYPE" ]; do
      center_block "Select server type:
  1) Headless Server — CLI only, no desktop environment
  2) GUI Server      — GNOME desktop environment"
      echo ""
      printf "Enter choice [1-2] or name (headless / gui): "
      read -r INPUT </dev/tty
      case "${INPUT,,}" in
        1|headless) SERVER_TYPE="headless" ;;
        2|gui)      SERVER_TYPE="gui"     ;;
        *)
          render_header
          echo -e "${RED}Invalid selection '${INPUT}'. Choose 1 or 2.${RESET}"
          ;;
      esac
    done
  fi

  if [ "$SERVER_TYPE" = "headless" ]; then
    ROLE="headless-server"
  fi
fi

# ---------- Stateless role: auto-detect context and invoke correct script ----
if [ "$ROLE" = "stateless" ]; then
  ROOT_FSTYPE=$(findmnt -n -o FSTYPE / 2>/dev/null || true)
  # Distinguish live ISO (tmpfs + no /nix mount) from running stateless system
  # (tmpfs + /nix mounted on btrfs subvol @nix).
  NIX_FSTYPE=$(findmnt -n -o FSTYPE /nix 2>/dev/null || true)
  if [ "$ROOT_FSTYPE" = "tmpfs" ] && [ "$NIX_FSTYPE" = "btrfs" ]; then
    # Already running a stateless (impermanence) system — just rebuild with new variant.
    # Fall through to GPU selection and nixos-rebuild switch below.
    echo ""
    echo -e "${CYAN}Stateless system detected — will switch variant via nixos-rebuild.${RESET}"
  elif [ "$ROOT_FSTYPE" = "tmpfs" ]; then
    # Running from NixOS live ISO — full disk setup
    echo ""
    echo -e "${CYAN}Live ISO detected — launching stateless disk setup (erases target disk)...${RESET}"
    echo ""
    curl -fsSL "https://raw.githubusercontent.com/VictoryTek/vexos-nix/${VEXOS_REV}/scripts/stateless-setup.sh" | bash
    exit 0
  else
    # Running on an existing NixOS install — in-place Btrfs migration
    echo ""
    echo -e "${CYAN}Existing install detected — launching in-place stateless migration...${RESET}"
    echo ""
    # sudo resets the environment by default, so plain `export` above would not
    # reach this child — pass VEXOS_REV explicitly on the sudo command line.
    curl -fsSL "https://raw.githubusercontent.com/VictoryTek/vexos-nix/${VEXOS_REV}/scripts/migrate-to-stateless.sh" | sudo VEXOS_REV="${VEXOS_REV}" bash
    exit 0
  fi
fi

# ---------- GPU variant selection --------------------------------------------
VARIANT=""
if [ "$ROLE" = "desktop" ] || [ "$ROLE" = "htpc" ] || [ "$ROLE" = "server" ] || [ "$ROLE" = "headless-server" ] || [ "$ROLE" = "stateless" ] || [ "$ROLE" = "vanilla" ]; then
  render_header
  if [ -n "$GUM" ]; then
    VARIANT="$(ui_choose "Select your GPU variant" \
      "amd:AMD    — AMD GPU (RADV, ROCm, LACT)" \
      "nvidia:NVIDIA — NVIDIA GPU (proprietary, open kernel modules)" \
      "intel:Intel  — Intel iGPU or Arc dGPU" \
      "vm:VM     — QEMU/KVM or VirtualBox guest")"
  else
    while [ -z "$VARIANT" ]; do
      center_block "Select your GPU variant:
  1) AMD    — AMD GPU (RADV, ROCm, LACT)
  2) NVIDIA — NVIDIA GPU (proprietary, open kernel modules)
  3) Intel  — Intel iGPU or Arc dGPU
  4) VM     — QEMU/KVM or VirtualBox guest"
      echo ""
      printf "Enter choice [1-4] or name (amd / nvidia / intel / vm): "
      read -r INPUT </dev/tty
      case "${INPUT,,}" in          # ${var,,} = lowercase (bash 4+)
        1|amd)    VARIANT="amd"    ;;
        2|nvidia) VARIANT="nvidia" ;;
        3|intel)  VARIANT="intel"  ;;
        4|vm)     VARIANT="vm"     ;;
        *)
          render_header
          echo -e "${RED}Invalid selection '${INPUT}'. Please enter 1, 2, 3, 4, amd, nvidia, intel, or vm.${RESET}"
          ;;
      esac
    done
  fi
fi

# ---------- NVIDIA driver branch selection -----------------------------------
# Vanilla always uses the kernel nouveau driver — no proprietary driver branches.
NVIDIA_SUFFIX=""
if [ "$VARIANT" = "nvidia" ]; then
  render_header
  echo -e "${YELLOW}Not sure? Check: https://www.nvidia.com/en-us/drivers/unix/legacy-gpu/${RESET}"
  echo -e "${YELLOW}Wrong choice? Run this installer again and switch.${RESET}"
  echo ""

  if [ -n "$GUM" ]; then
    NVIDIA_SUFFIX="$(ui_choose "Select NVIDIA driver branch" \
      ":Latest     — RTX, GTX 16xx, GTX 750 and newer" \
      "-legacy535:Legacy 535 — Maxwell/Pascal/Volta (LTS 535.x)")"
  else
    while true; do
      center_block "Select NVIDIA driver branch:
  1) Latest     — RTX, GTX 16xx, GTX 750 and newer
  2) Legacy 535 — Maxwell/Pascal/Volta (LTS 535.x)"
      echo ""
      printf "Enter choice [1-2]: "
      read -r INPUT </dev/tty
      case "${INPUT}" in
        1) NVIDIA_SUFFIX="";           break ;;
        2) NVIDIA_SUFFIX="-legacy535"; break ;;
        *)
          render_header
          echo -e "${YELLOW}Not sure? Check: https://www.nvidia.com/en-us/drivers/unix/legacy-gpu/${RESET}"
          echo -e "${YELLOW}Wrong choice? Run this installer again and switch.${RESET}"
          echo ""
          echo -e "${RED}Invalid selection '${INPUT}'. Choose 1 or 2.${RESET}"
          ;;
      esac
    done
  fi
fi

# ---------- ASUS ROG/TUF hardware ------------------------------------------
ASUS_ENABLE=false
ASUS_LAPTOP=false
if [ "$VARIANT" != "vm" ]; then
  render_header
  echo -e "${BOLD}Is this an ASUS ROG/TUF device?${RESET}"
  echo "  Laptop: enables asusd (fan curves, charge limit), supergfxctl, power-profiles-daemon"
  echo "  Desktop: enables OpenRGB for ASUS Aura motherboard RGB control"
  echo ""
  if [ -n "$GUM" ]; then
    if ui_confirm "ASUS ROG/TUF device?"; then ASUS_ENABLE=true; else ASUS_ENABLE=false; fi
  else
    printf "ASUS ROG/TUF device? [y/N] "
    read -r INPUT </dev/tty
    case "${INPUT,,}" in
      y|yes) ASUS_ENABLE=true ;;
      *)     ASUS_ENABLE=false ;;
    esac
  fi

  if [ "$ASUS_ENABLE" = "true" ]; then
    render_header
    if [ -n "$GUM" ]; then
      if ui_confirm "Is this device a laptop?"; then ASUS_LAPTOP=true; else ASUS_LAPTOP=false; fi
    else
      printf "Is this device a laptop? [y/N] "
      read -r INPUT </dev/tty
      case "${INPUT,,}" in
        y|yes) ASUS_LAPTOP=true ;;
        *)     ASUS_LAPTOP=false ;;
      esac
    fi
  fi
fi

FLAKE_TARGET="vexos-${ROLE}-${VARIANT}${NVIDIA_SUFFIX}"

# Always use 'boot' instead of 'switch': nixos-rebuild switch restarts
# display-manager.service during switch-to-configuration, which kills the live ISO's
# GNOME session and logs the user out. Using 'boot' installs the new generation as
# default without runtime activation; the user reboots into the new system.
REBUILD_ACTION="boot"

# ---------- Build & switch ---------------------------------------------------
render_header
echo -e "${BOLD}Building ${CYAN}${FLAKE_TARGET}${RESET}${BOLD} (action: ${REBUILD_ACTION})...${RESET}"
echo -e "${YELLOW}Using 'nixos-rebuild boot' to preserve the live session. The new system will not activate until you reboot.${RESET}"
render_progress "Preparing system..." 1 4

# ---------- UEFI / BIOS preflight check -------------------------------------
# vexos-nix defaults to systemd-boot (UEFI). On Legacy BIOS machines we patch
# /etc/nixos/flake.nix to use GRUB before building.
if [ ! -d /sys/firmware/efi ]; then
  echo -e "${YELLOW}${BOLD}⚠ Legacy BIOS / non-UEFI system detected.${RESET}"
  echo ""
  echo "  vexos-nix defaults to systemd-boot (UEFI). This machine will be"
  echo "  configured to use GRUB instead."
  echo ""
  echo "  Disk layout for GRUB (Legacy BIOS):"
  lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT 2>/dev/null || true
  echo ""
  echo "  GRUB is installed to the MBR of a whole disk (e.g. /dev/sda),"
  echo "  not a partition. Provide the disk device, not a partition number."
  echo ""
  GRUB_DEVICE=""
  while [ -z "$GRUB_DEVICE" ]; do
    if [ -n "$GUM" ]; then
      GRUB_DEVICE="$(ui_input "Enter disk device for GRUB" "/dev/sda, /dev/nvme0n1")"
    else
      printf "  Enter disk device for GRUB (e.g. /dev/sda, /dev/nvme0n1): "
      read -r GRUB_DEVICE </dev/tty
    fi
    if [ ! -b "$GRUB_DEVICE" ]; then
      echo -e "  ${RED}'${GRUB_DEVICE}' is not a block device. Try again.${RESET}"
      GRUB_DEVICE=""
    fi
  done
  echo ""
  echo "  Patching /etc/nixos/flake.nix to use GRUB on ${GRUB_DEVICE}..."
  # Replace the bootloaderModule block using awk (always available on NixOS ISO).
  # Tracks brace depth to reliably skip the old block regardless of comments/content.
  # Use vexos.bootloader / vexos.grub.device options so modules/system.nix owns
  # the actual boot.loader.* assignments — avoids equal-priority option conflicts.
  awk -v device="$GRUB_DEVICE" '
    /^    bootloaderModule = \{ \.\.\. \}: \{/ {
      print "    bootloaderModule = { ... }: {"
      print "      vexos.bootloader  = \"grub\";"
      print "      vexos.grub.device = \"" device "\";"
      print "    };"
      in_block = 1
      depth = 1
      next
    }
    in_block {
      for (i = 1; i <= length($0); i++) {
        c = substr($0, i, 1)
        if (c == "{") depth++
        else if (c == "}") depth--
      }
      if (depth <= 0) in_block = 0
      next
    }
    { print }
  ' /etc/nixos/flake.nix > /tmp/vexos-flake.tmp
  if ! grep -q 'grub' /tmp/vexos-flake.tmp; then
    echo -e "  ${RED}✗ Patch failed — bootloaderModule block not found in flake.nix.${RESET}" >&2
    rm -f /tmp/vexos-flake.tmp
    exit 1
  fi
  sudo mv /tmp/vexos-flake.tmp /etc/nixos/flake.nix
  echo -e "  ${GREEN}✓ flake.nix updated for GRUB (${GRUB_DEVICE}).${RESET}"
  echo ""
else
  # UEFI system — ensure /boot (EFI system partition) is mounted before building.
  if ! findmnt /boot >/dev/null 2>&1; then
    echo -e "${YELLOW}${BOLD}⚠ /boot is not mounted.${RESET}"
    echo ""
    echo "  The EFI system partition must be mounted at /boot before building."
    echo "  Identify your EFI partition (small FAT32, usually 512M–1G):"
    echo ""
    lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT 2>/dev/null || true
    echo ""
    if [ -n "$GUM" ]; then
      EFI_DEV="$(ui_input "Enter EFI partition device" "/dev/sda1, /dev/nvme0n1p1")"
    else
      printf "  Enter EFI partition device (e.g. /dev/sda1, /dev/nvme0n1p1): "
      read -r EFI_DEV </dev/tty
    fi
    if [ -b "$EFI_DEV" ]; then
      echo "  Mounting ${EFI_DEV} at /boot..."
      sudo mount "$EFI_DEV" /boot
      echo -e "  ${GREEN}✓ /boot mounted.${RESET}"
      echo ""
    else
      echo -e "  ${RED}✗ '${EFI_DEV}' is not a block device. Mount /boot manually and re-run.${RESET}"
      exit 1
    fi
  fi
fi

# ---------- ASUS hardware patch ---------------------------------------------
if [ "$ASUS_ENABLE" = "true" ]; then
  if grep -qF 'hardwareModule = { ... }: { };' /etc/nixos/flake.nix 2>/dev/null; then
    echo ""
    if [ "$ASUS_LAPTOP" = "true" ]; then
      echo "  Patching /etc/nixos/flake.nix to enable ASUS ROG/TUF laptop support..."
      sudo sed -i 's/hardwareModule = { \.\.\. }: { };/hardwareModule = { ... }: { vexos.hardware.asus.enable = true; vexos.hardware.asus.batteryChargeLimit = 80; };/' /etc/nixos/flake.nix
      echo -e "  ${GREEN}✓ ASUS laptop support enabled (battery charge limit set to 80%).${RESET}"
    else
      echo "  Patching /etc/nixos/flake.nix to enable OpenRGB for ASUS desktop..."
      sudo sed -i 's/hardwareModule = { \.\.\. }: { };/hardwareModule = { pkgs, ... }: { environment.systemPackages = [ pkgs.openrgb-with-all-plugins ]; boot.kernelModules = [ "i2c-dev" ]; services.udev.packages = [ pkgs.openrgb-with-all-plugins ]; };/' /etc/nixos/flake.nix
      echo -e "  ${GREEN}✓ OpenRGB enabled for ASUS desktop Aura RGB control.${RESET}"
    fi
    echo ""
  else
    echo ""
    echo -e "  ${YELLOW}⚠ hardwareModule not found in /etc/nixos/flake.nix — skipping ASUS patch.${RESET}"
    echo "    To enable ASUS support manually, add to your /etc/nixos/flake.nix:"
    if [ "$ASUS_LAPTOP" = "true" ]; then
      echo "      vexos.hardware.asus.enable = true;"
      echo "      vexos.hardware.asus.batteryChargeLimit = 80;"
    else
      echo "      environment.systemPackages = [ pkgs.openrgb-with-all-plugins ];"
      echo "      boot.kernelModules = [ \"i2c-dev\" ];"
      echo "      services.udev.packages = [ pkgs.openrgb-with-all-plugins ];"
    fi
    echo ""
  fi
fi

# ---------- hostId substitution ----------------------------------------------
# Replace the XXXXXXXX placeholder in /etc/nixos/flake.nix with the first 8 hex
# characters of /etc/machine-id. Required for ZFS pool identity on server and
# headless-server roles. Safe no-op for all other roles.
if [ -f /etc/nixos/flake.nix ] && grep -qF '"XXXXXXXX"' /etc/nixos/flake.nix 2>/dev/null; then
  HOST_ID="$(head -c 8 /etc/machine-id)"
  sudo sed -i "s/networking\.hostId = \"XXXXXXXX\"/networking.hostId = \"${HOST_ID}\"/" /etc/nixos/flake.nix
  echo -e "  ${GREEN}✓ hostId set to ${HOST_ID}.${RESET}"
fi

# ---------- Ensure git is available -------------------------------------------
# Stock NixOS installs do not include git in the system profile; the live ISO
# does. Fetch it from the binary cache when missing and use the absolute store
# path so sudo finds it regardless of secure_path/env_reset.
if command -v git >/dev/null 2>&1; then
  GIT="git"
else
  echo ""
  echo -e "${CYAN}git not found on this system — fetching from nixpkgs binary cache...${RESET}"
  _GIT_STORE="$(nix --extra-experimental-features 'nix-command flakes' \
    build nixpkgs#git --no-link --print-out-paths)"
  GIT="$_GIT_STORE/bin/git"
  export PATH="$_GIT_STORE/bin:$PATH"
fi

# Remove any kernel-install-override.nix left by previous installer versions.
# The current installer does not write a kernel override; any leftover file forces
# the wrong kernel (LTS) and must not enter the git index.
sudo rm -f /etc/nixos/kernel-install-override.nix

# ---------- Git-track /etc/nixos (excludes secrets from Nix store) -----------
# git+file:// only copies tracked files; untracked secrets/ never enter the store.
if ! sudo "$GIT" -C /etc/nixos rev-parse --git-dir &>/dev/null 2>&1; then
  echo ""
  echo -e "${CYAN}Initializing /etc/nixos as a git repository...${RESET}"
  # NOTE: hardware-configuration.nix and the override .nix files MUST be
  # git-tracked — the template flake imports them from the flake source, and
  # git+file:// copies only tracked files into the store. Only secrets/ (read
  # outside the flake source) stays untracked.
  sudo tee /etc/nixos/.gitignore > /dev/null << 'GITIGNORE'
secrets/
*.bak
vexos-variant
GITIGNORE
  sudo "$GIT" -C /etc/nixos init -q
  sudo "$GIT" -C /etc/nixos add .
  sudo "$GIT" -C /etc/nixos \
    -c user.email="vexos@localhost" \
    -c user.name="VexOS" \
    commit -q -m "chore: track /etc/nixos configuration"
  echo -e "${GREEN}✓ /etc/nixos is now git-tracked — secrets/ excluded from Nix store.${RESET}"
fi

# Ensure all flake-imported files are git-tracked and staged before any
# git+file:// evaluation.  This handles both:
#   a) Older repos created before flake.nix/flake.lock were tracked (legacy repair)
#   b) Re-runs of the installer where flake.nix was re-downloaded and patched
#      (hostId, ASUS, GRUB) but not yet re-staged — git+file:// would otherwise
#      evaluate the stale committed version, ignoring the fresh patches.
for f in flake.nix hardware-configuration.nix stateless-user-override.nix features.nix; do
  if [ -f "/etc/nixos/$f" ]; then
    sudo "$GIT" -C /etc/nixos add -f "$f"
  fi
done

# ---------- Flake lock refresh -----------------------------------------------
# Always resolve vexos-nix to the latest HEAD before dry-building.
# A stale /etc/nixos/flake.lock from a previous (failed) install attempt would
# otherwise pin the flake to an old revision, potentially pulling in packages
# that have since been removed from the repo.
render_progress "Refreshing flake inputs..." 2 4
if [ -n "$GUM" ]; then
  "$GUM" spin --title "Refreshing flake inputs..." -- \
    sudo nix --extra-experimental-features "nix-command flakes" \
    flake update --flake git+file:///etc/nixos
else
  echo -e "${CYAN}Refreshing flake inputs...${RESET}"
  sudo nix --extra-experimental-features "nix-command flakes" \
    flake update --flake git+file:///etc/nixos
fi

# Stage the refreshed lock file so all subsequent git+file:// evaluations see it.
sudo "$GIT" -C /etc/nixos add flake.lock

# ---------- Build & switch ---------------------------------------------------
# Cache check: dry-build first to see what would need to be compiled locally.
# Run a dry-build to surface anything that will be compiled locally rather than
# fetched from cache. This is informational only — the install proceeds regardless.
# Two derivation classes always build locally and are expected:
#   • Proprietary NVIDIA userspace (nvidia-x11 / NVIDIA-*.run / nvidia-settings /
#     nvidia-persistenced): unfree and non-redistributable, so Hydra never caches it.
#     The open kernel module (nvidia-open) IS cached and is fetched, not built.
#   • Patched OpenRazer: a local overlay patch (modules/razer.nix), so its hash never
#     matches an upstream cached build.
# Everything else is a transient Hydra lag and will typically be fast (binary
# downloads for Electron apps, short Rust/Python crate builds, etc.).
render_progress "Checking build cache..." 3 4
_DRY_OUT_FILE="$(mktemp)"
if [ -n "$GUM" ]; then
  "$GUM" spin --title "Checking what will be fetched vs built locally..." -- \
    bash -c "sudo nixos-rebuild dry-build --flake 'git+file:///etc/nixos#${FLAKE_TARGET}' >'${_DRY_OUT_FILE}' 2>&1 || true"
else
  echo -e "${CYAN}Checking what will be fetched vs built locally...${RESET}"
  sudo nixos-rebuild dry-build --flake "git+file:///etc/nixos#${FLAKE_TARGET}" >"${_DRY_OUT_FILE}" 2>&1 || true
fi
DRY_OUT="$(cat "${_DRY_OUT_FILE}")"
rm -f "${_DRY_OUT_FILE}"
SOURCE_BUILDS=$(printf '%s\n' "$DRY_OUT" \
  | awk '/will be built:/{p=1;next} /will be fetched:|^building |^[^ \t]/{p=0} p && /\/nix\/store\//{sub(/.*\/nix\/store\/[a-z0-9]+-/,""); print}' \
  | grep -E -- '-[0-9]+\.[0-9]+' \
  || true)

if [ -n "$SOURCE_BUILDS" ]; then
  # Also defined in pkgs/vexos-update/default.nix's UNAVOIDABLE_REGEX (kept in
  # sync manually — this script runs standalone via `curl | bash` before NixOS
  # is installed, with no local repo present to source a shared fragment from).
  UNAVOIDABLE_REGEX='^(NVIDIA-Linux-|nvidia-x11-|nvidia-settings-|nvidia-persistenced-|openrazer-[0-9])'
  UNAVOIDABLE=$(printf '%s\n' "$SOURCE_BUILDS" | grep -E "$UNAVOIDABLE_REGEX" || true)
  OTHER=$(printf '%s\n' "$SOURCE_BUILDS" | grep -Ev "$UNAVOIDABLE_REGEX" || true)

  if [ -n "$UNAVOIDABLE" ]; then
    echo ""
    echo -e "${CYAN}The following will build locally (expected — never in binary cache):"
    echo -e "NVIDIA's proprietary userspace is unfree/non-redistributable; the patched"
    echo -e "OpenRazer module is a local patch. The open NVIDIA kernel module IS fetched"
    echo -e "from cache. One-time build of ~10-15 min (seconds without NVIDIA).${RESET}"
    echo ""
    printf '%s\n' "$UNAVOIDABLE" | sed 's/^/    /'
    echo ""
  fi

  if [ -n "$OTHER" ]; then
    echo ""
    echo -e "${YELLOW}The following are not yet in the binary cache and will build locally."
    echo -e "Most are binary repacks or short crate builds and will complete quickly.${RESET}"
    echo ""
    printf '%s\n' "$OTHER" | sed 's/^/    /'
    echo ""
  fi
else
  echo -e "${GREEN}✓ All packages available in binary cache.${RESET}"
fi
render_header
if run_live_build "Building ${FLAKE_TARGET}..." \
     sudo nixos-rebuild "${REBUILD_ACTION}" --flake "git+file:///etc/nixos#${FLAKE_TARGET}"; then
  echo ""
  echo -e "${GREEN}${BOLD}✓ Build complete. New generation registered as default.${RESET}"
  echo -e "${YELLOW}Reboot now to activate the new system. Your current session will remain active until you do.${RESET}"
  if [ -f /etc/nixos/kernel-install-override.nix ]; then
    echo ""
    NV_NOTE=$(grep -oP "nvidiaDriverVariant = \"\K[^\"]*" /etc/nixos/kernel-install-override.nix 2>/dev/null || true)
    if [ -n "$NV_NOTE" ]; then
      echo -e "${YELLOW}Note: installed with channel-default kernel and NVIDIA driver variant '${NV_NOTE}'."
    else
      echo -e "${YELLOW}Note: installed with channel-default kernel (linuxPackages)."
    fi
    echo -e "Run 'just update' or use the Up app after reboot to upgrade to the"
    echo -e "target versions automatically once packages are cached (1-3 days).${RESET}"
  fi
  echo ""
  REBOOT_NOW=true
  if [ -n "$GUM" ]; then
    ui_confirm "Reboot now?" || REBOOT_NOW=false
  else
    printf "Reboot now? [Y/n] "
    read -r REBOOT_CHOICE </dev/tty
    REBOOT_CHOICE="${REBOOT_CHOICE%$'\r'}"
    case "${REBOOT_CHOICE,,}" in
      n|no) REBOOT_NOW=false ;;
      *)    REBOOT_NOW=true ;;
    esac
  fi
  if [ "$REBOOT_NOW" = "true" ]; then
    echo "Rebooting..."
    systemctl reboot
  else
    echo -e "${YELLOW}Reboot skipped. Run 'systemctl reboot' when ready.${RESET}"
  fi
else
  echo ""
  echo -e "${RED}${BOLD}✗ nixos-rebuild ${REBUILD_ACTION} failed.${RESET}"
  echo "  Last 60 lines of the build log (${BUILD_LOG_PATH}):"
  echo ""
  tail -n 60 "${BUILD_LOG_PATH}" 2>/dev/null || true
  echo ""
  echo -e "${RED}${BOLD}Reboot skipped.${RESET}"
  echo "  Review the full log above/at ${BUILD_LOG_PATH} and retry:"
  echo "    sudo nixos-rebuild ${REBUILD_ACTION} --flake /etc/nixos#${FLAKE_TARGET}"
  echo ""
  exit 1
fi
