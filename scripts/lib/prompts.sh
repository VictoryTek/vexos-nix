#!/usr/bin/env bash
# =============================================================================
# scripts/lib/prompts.sh — shared interactive prompts for the installer scripts
# (install.sh, stateless-setup.sh, migrate-to-stateless.sh).
#
# Sourced via scripts/lib/bootstrap.sh, never executed. Expects the colour
# variables from bootstrap.sh and render_header / center_block from
# lib/progress.sh (which defines plain fallbacks for both).
#
# Every ask_* function stores its answer in a global instead of printing it:
# the numbered fallback menu writes to the terminal, and inside `$( )` that
# output would be swallowed.
#
# Best-effort gum: init_gum sets $GUM when gum is available, and each prompt
# uses arrow-key selection then. Without it, every prompt falls back to a plain
# read-based one.
#
# VEXOS_PROMPT_STYLE selects the look, so each script keeps the UI it had:
#   full   — redraw the branded header before each prompt and centre the menu
#            text (install.sh)
#   plain  — left-aligned lists, no screen clears (default; stateless scripts)
# =============================================================================
# shellcheck disable=SC2034  # answers are globals consumed by the calling script

GUM=""

# ---------- gum (nice interactive prompts, best-effort) ----------------------
# Fetched at runtime from the nixpkgs binary cache, same pattern as the git
# fallback in install.sh. If unavailable (offline, cache unreachable) $GUM stays
# empty and every prompt below uses its plain read-based form.
init_gum() {
  local store
  if command -v gum >/dev/null 2>&1; then
    GUM="gum"
  else
    store="$(nix --extra-experimental-features 'nix-command flakes' \
      build nixpkgs#gum --no-link --print-out-paths 2>/dev/null || true)"
    if [ -n "$store" ] && [ -x "$store/bin/gum" ]; then
      GUM="$store/bin/gum"
    fi
  fi
}

# ui_choose "$title" "value[,alias…]:label" … — prints $title, lets the user
# arrow-key through the labels, echoes the chosen value on stdout.
# --padding indents the widget by $HEADER_PAD to roughly line up with the
# centered logo above it — gum has no --align flag for interactive widgets,
# only --padding, so this approximates centering rather than reflowing it.
ui_choose() {
  local title="$1"; shift
  local values=() labels=()
  local pair v
  for pair in "$@"; do
    v="${pair%%:*}"
    values+=("${v%%,*}")
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

_prompt_full() { [ "${VEXOS_PROMPT_STYLE:-plain}" = "full" ]; }

# Start a fresh prompt: branded header (full) or a blank separator line (plain).
_prompt_break() {
  if _prompt_full; then render_header; else echo ""; fi
}

# ask_choice VAR "title" "default" "preamble" "value[,alias…]:label" …
# Stores the chosen value in VAR. Fallback input accepts the item number, the
# value, or any alias (case-insensitive); empty input picks "default" when one is
# given, otherwise re-asks. "preamble" (may be empty) is printed under the header
# on every redraw. Value names are listed in the prompt unless some value is
# empty or starts with '-' (a suffix rather than a name, e.g. NVIDIA branches).
ask_choice() {
  local __var="$1" title="$2" default="$3" preamble="$4"
  shift 4
  local values=() names=() labels=()
  local e v
  for e in "$@"; do
    v="${e%%:*}"
    values+=("${v%%,*}")
    names+=(",${v,,},")
    labels+=("${e#*:}")
  done

  local hint="" nameable=true
  for v in "${values[@]}"; do
    case "$v" in ""|-*) nameable=false ;; esac
  done
  if [ "$nameable" = true ]; then
    hint=" or name ($(printf '%s / ' "${values[@]}" | sed 's| / $||'))"
    if [ -n "$default" ]; then hint=" or name (default: ${default})"; fi
  fi

  local result="" picked=false draw=true input error="" i list
  if [ -n "${GUM:-}" ]; then
    _prompt_break
    [ -n "$preamble" ] && echo -e "$preamble"
    result="$(ui_choose "$title" "$@")"
  else
    while [ "$picked" = false ]; do
      if [ "$draw" = true ]; then
        _prompt_break
        [ -n "$preamble" ] && echo -e "$preamble"
        [ -n "$error" ] && echo -e "$error"
        if _prompt_full; then
          list="${title}:"
          for i in "${!labels[@]}"; do list+=$'\n'"  $((i + 1))) ${labels[$i]}"; done
          center_block "$list"
        else
          echo -e "${BOLD}${title}:${RESET}"
          for i in "${!labels[@]}"; do echo "  $((i + 1))) ${labels[$i]}"; done
        fi
        echo ""
        draw=false
      fi
      printf "Enter choice [1-%d]%s: " "${#values[@]}" "$hint"
      read -r input </dev/tty
      if [ -z "$input" ] && [ -n "$default" ]; then
        result="$default"; picked=true
      elif [[ "$input" =~ ^[0-9]+$ ]] && [ "$input" -ge 1 ] && [ "$input" -le "${#values[@]}" ]; then
        result="${values[$((input - 1))]}"; picked=true
      elif [ -n "$input" ]; then
        for i in "${!names[@]}"; do
          if [[ "${names[$i]}" == *",${input,,},"* ]]; then
            result="${values[$i]}"; picked=true; break
          fi
        done
      fi
      if [ "$picked" = false ]; then
        error="${RED}Invalid selection '${input}'. Enter 1-${#values[@]}"
        [ "$nameable" = true ] && error+=" or a name"
        error+=".${RESET}"
        # Full style redraws the whole screen (error included); plain style just
        # prints the error and re-asks, without reprinting the menu.
        if _prompt_full; then draw=true; else echo -e "$error"; error=""; fi
      fi
    done
  fi
  printf -v "$__var" '%s' "$result"
}

# ask_yes_no "prompt" — exit status 0 = yes, 1 = no; default is No.
ask_yes_no() {
  local input
  if [ -n "${GUM:-}" ]; then
    ui_confirm "$1"
    return
  fi
  printf "%s [y/N] " "$1"
  read -r input </dev/tty
  case "${input,,}" in
    y|yes) return 0 ;;
    *)     return 1 ;;
  esac
}

# ---------- Hardware / platform questions ------------------------------------

# ask_gpu_variant → VARIANT (amd | nvidia | intel | vm)
ask_gpu_variant() {
  ask_choice VARIANT "Select your GPU variant" "" "" \
    "amd:AMD    — AMD GPU (RADV, ROCm, LACT)" \
    "nvidia:NVIDIA — NVIDIA GPU (proprietary, open kernel modules)" \
    "intel:Intel  — Intel iGPU or Arc dGPU" \
    "vm:VM     — QEMU/KVM or VirtualBox guest"
}

# ask_nvidia_branch → NVIDIA_SUFFIX ("" for Latest, "-legacy580")
ask_nvidia_branch() {
  ask_choice NVIDIA_SUFFIX "Select NVIDIA driver branch" "" \
    "${YELLOW}Not sure? Check: https://www.nvidia.com/en-us/drivers/unix/legacy-gpu/${RESET}
${YELLOW}Wrong choice? Run this script again and switch.${RESET}
" \
    ":Latest     — RTX, GTX 16xx, GTX 750 and newer" \
    "-legacy580:Legacy 580 — Maxwell/Pascal/Volta (580.x, required)"
}

# ask_vm_platform → VM_PLATFORM (qemu | virtualbox)
# QEMU/KVM and VirtualBox need different guest packages, and VirtualBox pins the
# kernel to 6.18 LTS to keep its guest additions building. Asking up front means
# a Proxmox/QEMU guest keeps its role's own kernel instead of inheriting that
# pin. "qemu" is the vexos.vm.platform default, so callers only need to persist
# the answer when it is "virtualbox" (install.sh: features.nix; the stateless
# scripts: vm-platform.nix).
ask_vm_platform() {
  ask_choice VM_PLATFORM "Select your hypervisor" "" "" \
    "qemu,kvm,proxmox:QEMU/KVM  — Proxmox, libvirt, plain QEMU (guest agent + SPICE)" \
    "virtualbox,vbox:VirtualBox — Guest Additions, shared folders (pins kernel 6.18 LTS)"
}

# ask_asus → ASUS_ENABLE, ASUS_LAPTOP (true | false)
ask_asus() {
  ASUS_ENABLE=false
  ASUS_LAPTOP=false
  _prompt_break
  echo -e "${BOLD}Is this an ASUS ROG/TUF device?${RESET}"
  echo "  Laptop: enables asusd (fan curves, charge limit), supergfxctl, power-profiles-daemon"
  echo "  Desktop: enables OpenRGB for ASUS Aura motherboard RGB control"
  echo ""
  if ask_yes_no "ASUS ROG/TUF device?"; then ASUS_ENABLE=true; fi
  if [ "$ASUS_ENABLE" = "true" ]; then
    _prompt_break
    if ask_yes_no "Is this device a laptop?"; then ASUS_LAPTOP=true; fi
  fi
}

# ask_password → HASHED_PW (SHA-512 crypt of a password entered twice)
# The live ISO and stock NixOS installs don't ship openssl in PATH; fetch it from
# the binary cache when missing and use the absolute store path.
ask_password() {
  local openssl pw pw2
  if command -v openssl &>/dev/null; then
    openssl="openssl"
  else
    echo -e "${CYAN}openssl not found on this system — fetching from nixpkgs binary cache...${RESET}"
    openssl="$(nix --extra-experimental-features 'nix-command flakes' \
      build nixpkgs#openssl.bin --no-link --print-out-paths)/bin/openssl"
  fi
  while true; do
    printf "  Password (hidden): "
    read -rs pw </dev/tty
    echo ""
    if [ -z "$pw" ]; then
      echo -e "${RED}  Password cannot be empty. Please set a password.${RESET}"
      continue
    fi
    printf "  Confirm password:  "
    read -rs pw2 </dev/tty
    echo ""
    if [ "$pw" = "$pw2" ]; then
      HASHED_PW="$(printf '%s' "$pw" | "$openssl" passwd -6 -stdin)"
      echo -e "${GREEN}  ✓ Password accepted.${RESET}"
      break
    else
      echo -e "${RED}  Passwords do not match. Try again.${RESET}"
    fi
  done
}
