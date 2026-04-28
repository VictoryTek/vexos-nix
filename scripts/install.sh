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
echo "  4) Server  — Server (GUI or Headless)"
echo ""

ROLE=""
while [ -z "$ROLE" ]; do
  printf "Enter choice [1-4] or name (desktop / stateless / htpc / server): "
  read -r INPUT </dev/tty
  case "${INPUT,,}" in
    1|desktop)  ROLE="desktop"  ;;
    2|stateless) ROLE="stateless" ;;
    3|htpc)     ROLE="htpc"     ;;
    4|server)   ROLE="server"   ;;
    *)
      echo -e "${RED}Invalid selection '${INPUT}'. Choose 1-4 or a role name.${RESET}"
      ;;
  esac
done

# ---------- Server sub-type selection ----------------------------------------
if [ "$ROLE" = "server" ]; then
  echo ""
  echo -e "${BOLD}Select server type:${RESET}"
  echo "  1) Headless Server — CLI only, no desktop environment"
  echo "  2) GUI Server      — GNOME desktop environment"
  echo ""

  SERVER_TYPE=""
  while [ -z "$SERVER_TYPE" ]; do
    printf "Enter choice [1-2] or name (headless / gui): "
    read -r INPUT </dev/tty
    case "${INPUT,,}" in
      1|headless) SERVER_TYPE="headless" ;;
      2|gui)      SERVER_TYPE="gui"     ;;
      *)
        echo -e "${RED}Invalid selection '${INPUT}'. Choose 1 or 2.${RESET}"
        ;;
    esac
  done

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
    curl -fsSL https://raw.githubusercontent.com/VictoryTek/vexos-nix/main/scripts/stateless-setup.sh | bash
    exit 0
  else
    # Running on an existing NixOS install — in-place Btrfs migration
    echo ""
    echo -e "${CYAN}Existing install detected — launching in-place stateless migration...${RESET}"
    echo ""
    curl -fsSL https://raw.githubusercontent.com/VictoryTek/vexos-nix/main/scripts/migrate-to-stateless.sh | sudo bash
    exit 0
  fi
fi

# ---------- GPU variant selection --------------------------------------------
VARIANT=""
if [ "$ROLE" = "desktop" ] || [ "$ROLE" = "htpc" ] || [ "$ROLE" = "server" ] || [ "$ROLE" = "headless-server" ] || [ "$ROLE" = "stateless" ]; then
  echo ""
  echo -e "${BOLD}Select your GPU variant:${RESET}"
  echo "  1) AMD    — AMD GPU (RADV, ROCm, LACT)"
  echo "  2) NVIDIA — NVIDIA GPU (proprietary, open kernel modules)"
  echo "  3) Intel  — Intel iGPU or Arc dGPU"
  echo "  4) VM     — QEMU/KVM or VirtualBox guest"
  echo ""

  while [ -z "$VARIANT" ]; do
    printf "Enter choice [1-4] or name (amd / nvidia / intel / vm): "
    read -r INPUT </dev/tty
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

# ---------- NVIDIA driver branch selection -----------------------------------
NVIDIA_SUFFIX=""
if [ "$VARIANT" = "nvidia" ]; then
  echo ""
  echo -e "${BOLD}Select NVIDIA driver branch:${RESET}"
  echo "  1) Latest     — RTX, GTX 16xx, GTX 750 and newer"
  echo "  2) Legacy 535 — Maxwell/Pascal/Volta (LTS 535.x)"
  echo "  3) Legacy 470 — Kepler, GeForce 600/700 (470.x)"
  echo ""
  echo -e "${YELLOW}Not sure? Check: https://www.nvidia.com/en-us/drivers/unix/legacy-gpu/${RESET}"
  echo -e "${YELLOW}Wrong choice? Run this installer again and switch.${RESET}"
  echo ""

  while [ -z "$NVIDIA_SUFFIX" ]; do
    printf "Enter choice [1-3]: "
    read -r INPUT </dev/tty
    case "${INPUT}" in
      1) NVIDIA_SUFFIX=""             ;;
      2) NVIDIA_SUFFIX="-legacy535"   ;;
      3) NVIDIA_SUFFIX="-legacy470"   ;;
      *)
        echo -e "${RED}Invalid selection '${INPUT}'. Choose 1, 2, or 3.${RESET}"
        ;;
    esac
    [[ -n "${INPUT}" ]] && break
  done
fi

FLAKE_TARGET="vexos-${ROLE}-${VARIANT}${NVIDIA_SUFFIX}"

# ---------- Build & switch ---------------------------------------------------
echo ""
echo -e "${BOLD}Building ${CYAN}${FLAKE_TARGET}${RESET}${BOLD}...${RESET}"
echo ""

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
    printf "  Enter disk device for GRUB (e.g. /dev/sda, /dev/nvme0n1): "
    read -r GRUB_DEVICE </dev/tty
    if [ ! -b "$GRUB_DEVICE" ]; then
      echo -e "  ${RED}'${GRUB_DEVICE}' is not a block device. Try again.${RESET}"
      GRUB_DEVICE=""
    fi
  done
  echo ""
  echo "  Patching /etc/nixos/flake.nix to use GRUB on ${GRUB_DEVICE}..."
  # Replace the bootloaderModule block using awk (always available on NixOS ISO).
  # Tracks brace depth to reliably skip the old block regardless of comments/content.
  awk -v device="$GRUB_DEVICE" '
    /^    bootloaderModule = \{ \.\.\. \}: \{/ {
      print "    bootloaderModule = { ... }: {"
      print "      boot.loader.systemd-boot.enable = false;"
      print "      boot.loader.grub = {"
      print "        enable     = true;"
      print "        efiSupport = false;"
      print "        device     = \"" device "\";"
      print "      };"
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
    printf "  Enter EFI partition device (e.g. /dev/sda1, /dev/nvme0n1p1): "
    read -r EFI_DEV </dev/tty
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

# ---------- Build & switch ---------------------------------------------------
if sudo nixos-rebuild switch --flake "/etc/nixos#${FLAKE_TARGET}"; then
  echo ""
  echo -e "${GREEN}${BOLD}✓ Build and switch successful!${RESET}"
  echo ""
  printf "Reboot now? [y/N] "
  read -r REBOOT_CHOICE </dev/tty
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
