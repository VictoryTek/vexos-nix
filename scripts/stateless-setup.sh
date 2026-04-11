#!/usr/bin/env bash
# =============================================================================
# stateless-setup.sh — VexOS Stateless Role Initial Disk Setup
# Repository: https://github.com/VictoryTek/vexos-nix
#
# Usage (one-liner from NixOS live ISO, recommended):
#   bash <(curl -fsSL https://raw.githubusercontent.com/VictoryTek/vexos-nix/main/scripts/stateless-setup.sh)
#
# Or clone first and run locally:
#   bash scripts/stateless-setup.sh
#
# What this script does:
#   1. Partitions and formats the target disk (DESTRUCTIVE — all data erased)
#   2. Creates: EFI partition (512 MiB), LUKS2 container, Btrfs subvolumes
#      (@nix → /nix,  @persist → /persistent)
#   3. Runs nixos-generate-config --no-filesystems --root /mnt
#   4. Downloads the vexos-nix template flake to /mnt/etc/nixos/
#   5. Runs nixos-install targeting the chosen vexos-stateless-<variant>
#
# SECURITY NOTICE:
#   This script is fetched from raw.githubusercontent.com and executed directly.
#   Always verify the source URL above before running.
#   Source code: https://github.com/VictoryTek/vexos-nix/blob/main/scripts/stateless-setup.sh
# =============================================================================

set -euo pipefail

# Clean up temp files on exit (including on error)
cleanup() {
  rm -f /tmp/disk-password
}
trap cleanup EXIT

REPO_RAW="https://raw.githubusercontent.com/VictoryTek/vexos-nix/main"
TEMPLATE_URL="${REPO_RAW}/template/etc-nixos-flake.nix"
DISKO_TEMPLATE_URL="${REPO_RAW}/template/stateless-disko.nix"
DISKO_TMP="/tmp/vexos-stateless-disk.nix"

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
echo -e "${BOLD}${CYAN}============================================================${RESET}"
echo -e "${BOLD}${CYAN}   VexOS Stateless Role — Initial Disk Setup${RESET}"
echo -e "${BOLD}${CYAN}============================================================${RESET}"
echo ""
echo -e "${RED}${BOLD}  WARNING: This script will ERASE ALL DATA on the target disk.${RESET}"
echo -e "${YELLOW}  Run this from the NixOS live ISO, NOT on an existing system.${RESET}"
echo ""

# ---------- Ensure nix-command + flakes are enabled -------------------------
# The NixOS ISO may not have these experimental features enabled by default.
if ! nix run --help &>/dev/null 2>&1; then
  echo -e "${YELLOW}Enabling nix-command and flakes for this session...${RESET}"
  export NIX_CONFIG="experimental-features = nix-command flakes"
fi

# ---------- Show available disks --------------------------------------------
echo -e "${BOLD}Available block devices:${RESET}"
echo ""
lsblk -d -o NAME,SIZE,MODEL,TRAN 2>/dev/null | grep -v loop || lsblk -d -o NAME,SIZE,MODEL
echo ""

# ---------- Prompt: target disk ---------------------------------------------
DISK=""
while [ -z "$DISK" ]; do
  printf "Enter the disk device to install to (e.g. /dev/nvme0n1 or /dev/sda): "
  read -r DISK_INPUT
  if [[ ! "$DISK_INPUT" =~ ^/dev/ ]]; then
    echo -e "${RED}Device must start with /dev/ — e.g. /dev/nvme0n1${RESET}"
    DISK=""
    continue
  fi
  if [ ! -b "$DISK_INPUT" ]; then
    echo -e "${RED}Device '${DISK_INPUT}' not found or is not a block device.${RESET}"
    DISK=""
    continue
  fi
  DISK="$DISK_INPUT"
done

# ---------- Confirm disk selection by re-typing -----------------------------
echo ""
echo -e "${RED}${BOLD}  !! POINT OF NO RETURN !!${RESET}"
echo -e "${YELLOW}  ALL DATA on ${DISK} will be permanently destroyed.${RESET}"
echo ""
printf "To confirm, type the device path again exactly: "
read -r DISK_CONFIRM
if [ "$DISK_CONFIRM" != "$DISK" ]; then
  echo -e "${RED}Confirmation does not match. Aborting.${RESET}"
  exit 1
fi

# ---------- Prompt: GPU variant ---------------------------------------------
echo ""
echo -e "${BOLD}Select your GPU variant:${RESET}"
echo "  1) AMD    — AMD GPU (RADV, ROCm, LACT)"
echo "  2) NVIDIA — NVIDIA GPU (proprietary, open kernel modules)"
echo "  3) Intel  — Intel iGPU or Arc dGPU"
echo "  4) VM     — QEMU/KVM or VirtualBox guest"
echo ""

VARIANT=""
while [ -z "$VARIANT" ]; do
  printf "Enter choice [1-4] or name (amd / nvidia / intel / vm): "
  read -r INPUT
  case "${INPUT,,}" in
    1|amd)    VARIANT="amd"    ;;
    2|nvidia) VARIANT="nvidia" ;;
    3|intel)  VARIANT="intel"  ;;
    4|vm)     VARIANT="vm"     ;;
    *)
      echo -e "${RED}Invalid selection '${INPUT}'. Please enter 1, 2, 3, 4, amd, nvidia, intel, or vm.${RESET}"
      ;;
  esac
done

# ---------- Prompt: hostname -------------------------------------------------
echo ""
printf "Enter hostname [vexos-stateless]: "
read -r HOSTNAME_INPUT
HOSTNAME="${HOSTNAME_INPUT:-vexos-stateless}"

# ---------- Determine LUKS setting ------------------------------------------
if [ "$VARIANT" = "vm" ]; then
  LUKS_BOOL="false"
  echo ""
  echo -e "${CYAN}VM variant selected — disk encryption (LUKS2) will be skipped.${RESET}"
else
  LUKS_BOOL="true"
fi

# ---------- Summary and final confirmation ----------------------------------
echo ""
echo -e "${BOLD}Installation summary:${RESET}"
echo "  Disk:       ${DISK}"
echo "  GPU variant: ${VARIANT}"
echo "  Hostname:   ${HOSTNAME}"
echo "  LUKS:       ${LUKS_BOOL}"
echo "  Flake target: vexos-stateless-${VARIANT}"
echo ""
printf "Proceed with installation? This will ERASE ${DISK}. [yes/N] "
read -r PROCEED
if [ "${PROCEED}" != "yes" ]; then
  echo "Aborting."
  exit 0
fi

# ---------- Download disko template -----------------------------------------
echo ""
echo -e "${BOLD}Downloading disko configuration template...${RESET}"
curl -fsSL "${DISKO_TEMPLATE_URL}" -o "${DISKO_TMP}"
echo "  Saved to ${DISKO_TMP}"

# ---------- Run disko --------------------------------------------------------
echo ""
echo -e "${BOLD}${RED}DESTRUCTIVE STEP: Formatting ${DISK} with disko...${RESET}"
echo ""
sudo nix \
  --extra-experimental-features 'nix-command flakes' \
  run 'github:nix-community/disko/latest' -- \
  --mode destroy,format,mount \
  "${DISKO_TMP}" \
  --arg disk "\"${DISK}\"" \
  --arg enableLuks "${LUKS_BOOL}"

echo ""
echo -e "${GREEN}${BOLD}✓ Disk formatted and mounted at /mnt.${RESET}"

# ---------- Generate hardware configuration ---------------------------------
echo ""
echo -e "${BOLD}Generating hardware configuration (no filesystem entries)...${RESET}"
sudo nixos-generate-config --no-filesystems --root /mnt
echo -e "${GREEN}✓ hardware-configuration.nix generated at /mnt/etc/nixos/hardware-configuration.nix${RESET}"

# Set hostname in hardware config could be done in the flake; skip here.

# ---------- Download template flake -----------------------------------------
echo ""
echo -e "${BOLD}Downloading vexos-nix template flake to /mnt/etc/nixos/...${RESET}"
sudo curl -fsSL "${TEMPLATE_URL}" -o /mnt/etc/nixos/flake.nix
echo -e "${GREEN}✓ /mnt/etc/nixos/flake.nix downloaded.${RESET}"

# ---------- Run nixos-install ------------------------------------------------
FLAKE_TARGET="vexos-stateless-${VARIANT}"
echo ""
echo -e "${BOLD}Running nixos-install targeting ${CYAN}${FLAKE_TARGET}${RESET}${BOLD}...${RESET}"
echo -e "${YELLOW}This may take a while — it will download and build the NixOS closure.${RESET}"
echo ""
sudo nixos-install \
  --no-root-passwd \
  --flake "/mnt/etc/nixos#${FLAKE_TARGET}"

echo ""
echo -e "${GREEN}${BOLD}============================================================${RESET}"
echo -e "${GREEN}${BOLD}  ✓ VexOS Stateless installation complete!${RESET}"
echo -e "${GREEN}${BOLD}============================================================${RESET}"
echo ""
echo -e "${BOLD}Next steps:${RESET}"
echo "  1. Set a root password if needed:  nixos-enter --root /mnt -- passwd"
echo "  2. Remove the live ISO from your boot device."
echo "  3. Reboot: sudo reboot"
echo ""
echo -e "${YELLOW}${BOLD}IMPORTANT:${RESET} Store your LUKS passphrase in a secure location."
echo "  If you lose it, all data on the encrypted volume is unrecoverable."
echo ""
printf "Reboot now? [y/N] "
read -r REBOOT_CHOICE
case "${REBOOT_CHOICE,,}" in
  y|yes)
    echo "Rebooting..."
    sudo reboot
    ;;
  *)
    echo ""
    echo -e "${YELLOW}Skipping reboot. Run 'sudo reboot' when ready.${RESET}"
    echo ""
    ;;
esac
