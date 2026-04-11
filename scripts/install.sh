#!/usr/bin/env bash
# =============================================================================
# install.sh — vexos-nix Interactive First-Boot Installer
# Repository: https://github.com/VictoryTek/vexos-nix
#
# Usage (one-liner, recommended):
#   bash <(curl -fsSL https://raw.githubusercontent.com/VictoryTek/vexos-nix/main/scripts/install.sh)
#
# Or clone first and run locally:
#   bash scripts/install.sh
#
# Supported roles (expand this list as new roles are added to the flake):
#   desktop — Gaming/workstation (AMD, NVIDIA, Intel, VM)
#   stateless — Minimal/clean build, no gaming/dev/virt/ASUS modules (AMD, NVIDIA, Intel, VM)
#   htpc    — (coming soon)
#   server  — (coming soon)
#
# SECURITY NOTICE:
#   This script is fetched from raw.githubusercontent.com and executed directly.
#   Always verify the source URL above before running.
#   Source code: https://github.com/VictoryTek/vexos-nix/blob/main/scripts/install.sh
# =============================================================================

set -euo pipefail

SCRIPT_URL="https://raw.githubusercontent.com/VictoryTek/vexos-nix/main/scripts/install.sh"

# ---------- Color helpers (only if stdout is a TTY with color support) -------
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

# ---------- Header -----------------------------------------------------------
echo ""
echo -e "${BOLD}${CYAN}============================================${RESET}"
echo -e "${BOLD}${CYAN}   vexos-nix Interactive Installer${RESET}"
echo -e "${BOLD}${CYAN}============================================${RESET}"
echo ""
echo -e "${YELLOW}Source: ${SCRIPT_URL}${RESET}"
echo -e "${YELLOW}Verify: https://github.com/VictoryTek/vexos-nix/blob/main/scripts/install.sh${RESET}"
echo ""

# ---------- Role selection ---------------------------------------------------
# Only one role exists today; the selector is here so adding htpc/server later
# requires nothing more than uncommenting the extra options below.
echo -e "${BOLD}Select your role:${RESET}"
echo "  1) Desktop — Full gaming / workstation stack"
echo "  2) Stateless — Minimal build (no gaming / dev / virt / ASUS)"
echo "  3) HTPC    — Home theatre PC"
echo "  4) Server  — Headless server"
echo ""

ROLE=""
while [ -z "$ROLE" ]; do
  printf "Enter choice [1-4] or name (desktop / stateless / htpc / server): "
  read -r INPUT
  case "${INPUT,,}" in
    1|desktop) ROLE="desktop" ;;
    2|stateless) ROLE="stateless" ;;
    3|htpc)    ROLE="htpc"    ;;
    4|server)  ROLE="server"  ;;
    *)
      echo -e "${RED}Invalid selection '${INPUT}'. Choose 1-4 or a role name.${RESET}"
      ;;
  esac
done

# ---------- GPU variant selection (desktop and stateless roles) ----------------
VARIANT=""
if [ "$ROLE" = "desktop" ] || [ "$ROLE" = "stateless" ] || [ "$ROLE" = "htpc" ] || [ "$ROLE" = "server" ]; then
  echo ""
  echo -e "${BOLD}Select your GPU variant:${RESET}"
  echo "  1) AMD    — AMD GPU (RADV, ROCm, LACT)"
  echo "  2) NVIDIA — NVIDIA GPU (proprietary, open kernel modules)"
  echo "  3) Intel  — Intel iGPU or Arc dGPU"
  echo "  4) VM     — QEMU/KVM or VirtualBox guest"
  echo ""

  while [ -z "$VARIANT" ]; do
    printf "Enter choice [1-4] or name (amd / nvidia / intel / vm): "
    read -r INPUT
    case "${INPUT,,}" in          # ${var,,} = lowercase (bash 4+)
      1|amd)    VARIANT="amd"    ;;
      2|nvidia) VARIANT="nvidia" ;;
      3|intel)  VARIANT="intel"  ;;
      4|vm)     VARIANT="vm"     ;;
      *)
        echo -e "${RED}Invalid selection '${INPUT}'. Please enter 1, 2, 3, 4, amd, nvidia, intel, or vm.${RESET}"
        ;;
    esac
  done
fi

FLAKE_TARGET="vexos-${ROLE}-${VARIANT}"

# ---------- Stateless role: first-time install notice -------------------------
if [ "$ROLE" = "stateless" ]; then
  echo ""
  echo -e "${YELLOW}${BOLD}NOTE: Stateless role — getting started${RESET}"
  echo ""
  echo "  Two setup paths are available:"
  echo ""
  echo "  1) EXISTING NixOS install (recommended) — migrate in-place:"
  echo "       sudo bash <(curl -fsSL https://raw.githubusercontent.com/VictoryTek/vexos-nix/main/scripts/migrate-to-stateless.sh)"
  echo "     Creates Btrfs @nix/@persist subvolumes, updates hardware-configuration.nix,"
  echo "     and runs nixos-rebuild switch automatically. No disk wipe required."
  echo ""
  echo "  2) FRESH install from the NixOS live ISO:"
  echo "       bash <(curl -fsSL https://raw.githubusercontent.com/VictoryTek/vexos-nix/main/scripts/stateless-setup.sh)"
  echo "     Partitions the disk (FAT32 /boot + Btrfs root), generates hardware"
  echo "     config, and runs nixos-install. All data on the target disk will be erased."
  echo ""
  echo "  install.sh handles REBUILDS on an already-running vexos-stateless system."
  echo "  Press Enter to continue with rebuild, or Ctrl+C to abort."
  read -r _
fi

# ---------- Build & switch ---------------------------------------------------
echo ""
echo -e "${BOLD}Building ${CYAN}${FLAKE_TARGET}${RESET}${BOLD}...${RESET}"
echo ""

if sudo nixos-rebuild switch --flake "/etc/nixos#${FLAKE_TARGET}"; then
  echo ""
  echo -e "${GREEN}${BOLD}✓ Build and switch successful!${RESET}"
  echo ""
  printf "Reboot now? [y/N] "
  read -r REBOOT_CHOICE
  case "${REBOOT_CHOICE,,}" in
    y|yes)
      echo "Rebooting..."
      systemctl reboot
      ;;
    *)
      echo ""
      echo -e "${YELLOW}Skipping reboot. Log out and back in to apply session changes.${RESET}"
      echo ""
      ;;
  esac
else
  echo ""
  echo -e "${RED}${BOLD}✗ nixos-rebuild failed. Reboot skipped.${RESET}"
  echo "  Review the output above for errors and retry:"
  echo "    sudo nixos-rebuild switch --flake /etc/nixos#${FLAKE_TARGET}"
  echo ""
  exit 1
fi
