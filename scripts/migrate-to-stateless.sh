#!/usr/bin/env bash
# =============================================================================
# migrate-to-stateless.sh — VexOS Stateless In-Place Migration
# Repository: https://github.com/VictoryTek/vexos-nix
#
# Usage (run on an existing NixOS system — NOT from the live ISO):
#   curl -fsSL https://raw.githubusercontent.com/VictoryTek/vexos-nix/main/scripts/migrate-to-stateless.sh | sudo bash
# Or, if you have the repo cloned:
#   sudo bash scripts/migrate-to-stateless.sh
#
# What this script does:
#   1. Detects your existing Btrfs root partition and FAT32 /boot partition
#   2. Creates Btrfs subvolumes @nix (→/nix) and @persist (→/persistent)
#   3. Reflink-copies /nix into the @nix subvolume (instant copy-on-write)
#   4. Backs up and regenerates hardware-configuration.nix with the correct
#      UUID-based filesystem declarations for the stateless layout
#   5. Runs nixos-rebuild switch to activate the stateless configuration
#
# Partition requirements:
#   - FAT32 EFI partition mounted at /boot
#   - Btrfs root partition mounted at /
#   - No LUKS — encryption is not used in the stateless role
#
# SECURITY NOTICE:
#   Always review scripts before running as root.
#   Source: https://github.com/VictoryTek/vexos-nix/blob/main/scripts/migrate-to-stateless.sh
# =============================================================================

set -euo pipefail

# ---------- Color helpers (only if TTY with color support) -------------------
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

BTRFS_MOUNT="/mnt/vexos-migrate-btrfs"
HW_CONFIG="/etc/nixos/hardware-configuration.nix"
HW_CONFIG_BAK="${HW_CONFIG}.pre-stateless"

# ---------- Root check -------------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${RED}This script must be run as root (use sudo).${RESET}"
  exit 1
fi

# ---------- Header -----------------------------------------------------------
echo ""
echo -e "${BOLD}${CYAN}============================================================${RESET}"
echo -e "${BOLD}${CYAN}   VexOS Stateless Migration — In-Place Conversion${RESET}"
echo -e "${BOLD}${CYAN}============================================================${RESET}"
echo ""
echo -e "${YELLOW}  This script converts an existing NixOS install to the${RESET}"
echo -e "${YELLOW}  VexOS stateless (impermanence) layout without wiping your disk.${RESET}"
echo -e "${YELLOW}  Run this on your installed system — NOT from a live ISO.${RESET}"
echo ""

# ---------- Detect live ISO (abort if running from ISO) ---------------------
# Check if / is tmpfs (impermanence or live ISO) — abort if so
ROOT_FSTYPE=$(findmnt -n -o FSTYPE /)
if [ "$ROOT_FSTYPE" = "tmpfs" ]; then
  echo -e "${RED}Root filesystem is tmpfs.${RESET}"
  echo "  This looks like a NixOS live ISO or already-converted stateless system."
  echo "  Run this script on a standard NixOS installation, not from the ISO."
  exit 1
fi

# ---------- Detect btrfs tools -----------------------------------------------
if ! command -v btrfs &>/dev/null; then
  echo -e "${RED}btrfs-progs not found in PATH.${RESET}"
  echo "  Install with: nix-shell -p btrfs-progs"
  exit 1
fi

# ---------- Detect root Btrfs partition -------------------------------------
echo -e "${BOLD}Detecting disk layout...${RESET}"
echo ""

ROOT_DEVICE=$(findmnt -n -o SOURCE /)
ROOT_FSTYPE_CHECK=$(findmnt -n -o FSTYPE /)

if [ "$ROOT_FSTYPE_CHECK" != "btrfs" ]; then
  echo -e "${RED}Root filesystem is not Btrfs (found: ${ROOT_FSTYPE_CHECK}).${RESET}"
  echo "  VexOS stateless requires a Btrfs root partition."
  echo "  Partition your disk with a Btrfs root and re-install, then run this script."
  exit 1
fi

# Strip subvol or subvolid from the device if present (get the raw device)
ROOT_DEV_RAW=$(echo "$ROOT_DEVICE" | sed 's/\[.*//')

# ---------- Detect /boot FAT32 partition ------------------------------------
BOOT_DEVICE=$(findmnt -n -o SOURCE /boot 2>/dev/null || true)
BOOT_FSTYPE=$(findmnt -n -o FSTYPE /boot 2>/dev/null || true)

if [ -z "$BOOT_DEVICE" ]; then
  echo -e "${RED}No filesystem mounted at /boot.${RESET}"
  echo "  VexOS stateless requires a separate FAT32 EFI partition mounted at /boot."
  exit 1
fi

if [ "$BOOT_FSTYPE" != "vfat" ]; then
  echo -e "${YELLOW}Warning: /boot filesystem type is '${BOOT_FSTYPE}', expected 'vfat'.${RESET}"
  echo "  Continuing — you may need to adjust the /boot filesystem entry manually."
fi

# ---------- Get UUIDs --------------------------------------------------------
ROOT_UUID=$(blkid -s UUID -o value "$ROOT_DEV_RAW" 2>/dev/null || true)
BOOT_UUID=$(blkid -s UUID -o value "$BOOT_DEVICE" 2>/dev/null || true)

if [ -z "$ROOT_UUID" ]; then
  echo -e "${RED}Could not determine UUID for root device: ${ROOT_DEV_RAW}${RESET}"
  exit 1
fi
if [ -z "$BOOT_UUID" ]; then
  echo -e "${RED}Could not determine UUID for boot device: ${BOOT_DEVICE}${RESET}"
  exit 1
fi

echo "  Root device:  ${ROOT_DEV_RAW}  (UUID: ${ROOT_UUID})"
echo "  Boot device:  ${BOOT_DEVICE}  (UUID: ${BOOT_UUID})"
echo ""

# ---------- Check for existing subvolumes ------------------------------------
echo -e "${BOLD}Checking for existing @nix and @persist subvolumes...${RESET}"
mkdir -p "${BTRFS_MOUNT}"
mount -o subvolid=5 "${ROOT_DEV_RAW}" "${BTRFS_MOUNT}" 2>/dev/null || \
  mount "${ROOT_DEV_RAW}" "${BTRFS_MOUNT}"

EXISTING_NIX=false
EXISTING_PERSIST=false

if btrfs subvolume show "${BTRFS_MOUNT}/@nix" &>/dev/null; then
  EXISTING_NIX=true
  echo -e "${YELLOW}  @nix subvolume already exists.${RESET}"
fi
if btrfs subvolume show "${BTRFS_MOUNT}/@persist" &>/dev/null; then
  EXISTING_PERSIST=true
  echo -e "${YELLOW}  @persist subvolume already exists.${RESET}"
fi

umount "${BTRFS_MOUNT}"
rmdir "${BTRFS_MOUNT}" 2>/dev/null || true

if $EXISTING_NIX || $EXISTING_PERSIST; then
  echo ""
  echo -e "${YELLOW}One or more target subvolumes already exist — they will be SKIPPED.${RESET}"
fi
echo ""

# ---------- Summary and confirmation -----------------------------------------
echo -e "${BOLD}Migration summary:${RESET}"
echo "  Root partition: ${ROOT_DEV_RAW} (UUID: ${ROOT_UUID})"
echo "  Boot partition: ${BOOT_DEVICE} (UUID: ${BOOT_UUID})"
echo "  Will create:    @nix subvol → /nix"
echo "  Will create:    @persist subvol → /persistent"
echo "  Nix store copy: reflink (instant, same-filesystem)"
echo ""
echo -e "${YELLOW}${BOLD}  This will modify /etc/nixos/hardware-configuration.nix${RESET}"
echo -e "${YELLOW}  A backup will be saved to: ${HW_CONFIG_BAK}${RESET}"
echo ""

printf "Proceed with migration? [y/N] "
read -r PROCEED </dev/tty
case "${PROCEED,,}" in
  y|yes) ;;
  *)
    echo "Aborting."
    exit 0
    ;;
esac

# ---------- Mount raw Btrfs --------------------------------------------------
echo ""
echo -e "${BOLD}Mounting raw Btrfs filesystem...${RESET}"
mkdir -p "${BTRFS_MOUNT}"
mount -o subvolid=5 "${ROOT_DEV_RAW}" "${BTRFS_MOUNT}" 2>/dev/null || \
  mount "${ROOT_DEV_RAW}" "${BTRFS_MOUNT}"
echo -e "${GREEN}  Mounted ${ROOT_DEV_RAW} at ${BTRFS_MOUNT}${RESET}"

# ---------- Create @nix subvolume --------------------------------------------
if ! $EXISTING_NIX; then
  echo ""
  echo -e "${BOLD}Creating @nix subvolume...${RESET}"
  btrfs subvolume create "${BTRFS_MOUNT}/@nix"
  echo -e "${GREEN}  Created @nix${RESET}"
else
  echo ""
  echo -e "${YELLOW}Skipping @nix creation (already exists).${RESET}"
fi

# ---------- Create @persist subvolume ----------------------------------------
if ! $EXISTING_PERSIST; then
  echo ""
  echo -e "${BOLD}Creating @persist subvolume...${RESET}"
  btrfs subvolume create "${BTRFS_MOUNT}/@persist"
  echo -e "${GREEN}  Created @persist${RESET}"
else
  echo ""
  echo -e "${YELLOW}Skipping @persist creation (already exists).${RESET}"
fi

# ---------- Unmount raw Btrfs ------------------------------------------------
# Note: /nix is copied to @nix AFTER nixos-rebuild switch (below), so that
# the newly built stateless closure is included in the snapshot.
echo ""
echo -e "${BOLD}Unmounting raw Btrfs...${RESET}"
umount "${BTRFS_MOUNT}"
rmdir "${BTRFS_MOUNT}" 2>/dev/null || true
echo -e "${GREEN}  Unmounted.${RESET}"

# ---------- Back up hardware-configuration.nix --------------------------------
echo ""
echo -e "${BOLD}Backing up hardware-configuration.nix...${RESET}"
if [ ! -f "${HW_CONFIG}" ]; then
  echo -e "${RED}  ${HW_CONFIG} not found. Cannot continue.${RESET}"
  echo "  Ensure /etc/nixos/hardware-configuration.nix exists (generated by nixos-generate-config)."
  exit 1
fi
cp "${HW_CONFIG}" "${HW_CONFIG_BAK}"
echo -e "${GREEN}  Backed up to ${HW_CONFIG_BAK}${RESET}"

# ---------- Regenerate hardware-configuration.nix (no filesystems) ----------
echo ""
echo -e "${BOLD}Regenerating hardware-configuration.nix (without filesystem entries)...${RESET}"
nixos-generate-config --no-filesystems
echo -e "${GREEN}  Regenerated.${RESET}"

# ---------- Append stateless filesystem declarations -------------------------
echo ""
echo -e "${BOLD}Appending stateless filesystem declarations...${RESET}"

# Remove the final closing "}" from the generated file, then append our entries
# The generated hardware-configuration.nix ends with a single "}" on its own line
TMPFILE=$(mktemp)
# Strip trailing blank lines and the final "}"
perl -0777 -pe 's/\n\}\s*$/\n/' "${HW_CONFIG}" > "${TMPFILE}" 2>/dev/null || \
  head -n -1 "${HW_CONFIG}" > "${TMPFILE}"

cat >> "${TMPFILE}" << NIXEOF

  # ── Stateless filesystem layout ─────────────────────────────────────────
  # Written by scripts/migrate-to-stateless.sh — do not edit this block manually.
  # To revert: restore from ${HW_CONFIG_BAK}

  fileSystems."/boot" = {
    device  = "/dev/disk/by-uuid/${BOOT_UUID}";
    fsType  = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
  };

  fileSystems."/nix" = {
    device        = "/dev/disk/by-uuid/${ROOT_UUID}";
    fsType        = "btrfs";
    options       = [ "subvol=@nix" "compress=zstd" "noatime" ];
    neededForBoot = true;
  };

  fileSystems."/persistent" = {
    device        = "/dev/disk/by-uuid/${ROOT_UUID}";
    fsType        = "btrfs";
    options       = [ "subvol=@persist" "compress=zstd" "noatime" ];
    neededForBoot = true;
  };

}
NIXEOF

cp "${TMPFILE}" "${HW_CONFIG}"
rm -f "${TMPFILE}"
echo -e "${GREEN}  ✓ Filesystem declarations appended.${RESET}"

# ---------- GPU variant prompt -----------------------------------------------
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
  read -r INPUT </dev/tty
  case "${INPUT,,}" in
    1|amd)    VARIANT="amd"    ;;
    2|nvidia) VARIANT="nvidia" ;;
    3|intel)  VARIANT="intel"  ;;
    4|vm)     VARIANT="vm"     ;;
    *)
      echo -e "${RED}Invalid selection. Please enter 1, 2, 3, 4, amd, nvidia, intel, or vm.${RESET}"
      ;;
  esac
done

# ---------- Prompt: nimda user password -------------------------------------
CUSTOM_PASSWORD_SET=false
HASHED_PW=""

if command -v openssl &>/dev/null; then
  echo ""
  echo -e "${BOLD}Set a login password for the nimda user:${RESET}"
  echo -e "${YELLOW}  Press Enter twice to keep the default password ('vexos').${RESET}"
  echo -e "${YELLOW}  Note: the password resets to this value on every reboot (by design).${RESET}"
  echo ""
  while true; do
    printf "  Password (hidden): "
    read -rs PW </dev/tty
    echo ""
    if [ -z "$PW" ]; then
      echo -e "${YELLOW}  No password entered — keeping default 'vexos'.${RESET}"
      break
    fi
    printf "  Confirm password:  "
    read -rs PW2 </dev/tty
    echo ""
    if [ "$PW" = "$PW2" ]; then
      HASHED_PW=$(printf '%s' "$PW" | openssl passwd -6 -stdin)
      CUSTOM_PASSWORD_SET=true
      echo -e "${GREEN}  ✓ Password accepted.${RESET}"
      break
    else
      echo -e "${RED}  Passwords do not match. Try again.${RESET}"
    fi
  done
  if $CUSTOM_PASSWORD_SET; then
    echo ""
    echo -e "${BOLD}Writing /etc/nixos/stateless-user-override.nix...${RESET}"
    tee /etc/nixos/stateless-user-override.nix > /dev/null << NIXEOF
{ lib, ... }: {
  users.users.nimda.initialHashedPassword = lib.mkOverride 50 "${HASHED_PW}";
  users.users.nimda.initialPassword       = lib.mkForce null;
}
NIXEOF
    echo -e "${GREEN}  ✓ /etc/nixos/stateless-user-override.nix written.${RESET}"
  fi
else
  echo -e "${YELLOW}  openssl not found — skipping password setup (default 'vexos' will be used).${RESET}"
fi

# ---------- nixos-rebuild boot -----------------------------------------------
# CRITICAL: Use 'boot' instead of 'switch'.
# 'switch' would activate the stateless config immediately, restarting the
# display manager and killing this script before the /nix → @nix copy below.
# 'boot' installs the new generation as the next boot target without activating
# it, keeping the current session alive so the nix copy can complete.
echo ""
echo -e "${BOLD}Running nixos-rebuild boot (activates on next reboot)...${RESET}"
echo -e "${YELLOW}This may take a while on first run.${RESET}"
echo ""
nixos-rebuild boot --flake "/etc/nixos#vexos-stateless-${VARIANT}"

# ---------- Sync /nix → @nix (after rebuild, captures new closure) -----------
# This MUST happen after nixos-rebuild so the stateless-vm system closure
# (and any other newly built packages) are present in @nix before reboot.
# Without this, /nix after reboot would be missing the stateless generation
# and systemd would fail to spawn every service executor.
echo ""
echo -e "${BOLD}Syncing /nix into @nix subvolume (capturing newly built closure)...${RESET}"
echo -e "${CYAN}  Btrfs reflink — unchanged blocks are shared, only new data is written.${RESET}"
mkdir -p "${BTRFS_MOUNT}"
mount -o subvolid=5 "${ROOT_DEV_RAW}" "${BTRFS_MOUNT}" 2>/dev/null || \
  mount "${ROOT_DEV_RAW}" "${BTRFS_MOUNT}"
cp -a --reflink=always /nix/. "${BTRFS_MOUNT}/@nix/"
# Persist nixos config into @persist subvolume ---------------------------------
# /etc/nixos must be pre-populated in @persist so that after first stateless
# boot, the impermanence bind-mount (/persistent/etc/nixos → /etc/nixos)
# exposes flake.nix and hardware-configuration.nix for `just rebuild`/`just update`.
echo ""
echo -e "${BOLD}Persisting NixOS config files to @persist...${RESET}"
mkdir -p "${BTRFS_MOUNT}/@persist/etc/nixos"
cp /etc/nixos/flake.nix     "${BTRFS_MOUNT}/@persist/etc/nixos/" 2>/dev/null && \
  echo -e "  ${GREEN}✓ flake.nix persisted${RESET}" || \
  echo -e "  ${YELLOW}⚠ flake.nix not found — re-download after reboot${RESET}"
cp /etc/nixos/flake.lock    "${BTRFS_MOUNT}/@persist/etc/nixos/" 2>/dev/null || true
cp /etc/nixos/hardware-configuration.nix "${BTRFS_MOUNT}/@persist/etc/nixos/" 2>/dev/null && \
  echo -e "  ${GREEN}✓ hardware-configuration.nix persisted${RESET}" || \
  echo -e "  ${YELLOW}⚠ hardware-configuration.nix not found${RESET}"
cp /etc/nixos/stateless-user-override.nix "${BTRFS_MOUNT}/@persist/etc/nixos/" 2>/dev/null && \
  echo -e "  ${GREEN}✓ stateless-user-override.nix persisted${RESET}" || true
printf '%s' "vexos-stateless-${VARIANT}" > "${BTRFS_MOUNT}/@persist/etc/nixos/vexos-variant"
echo -e "  ${GREEN}✓ vexos-variant persisted${RESET}"
echo -e "${GREEN}  ✓ Config files persisted to @persist.${RESET}"
umount "${BTRFS_MOUNT}"
rmdir "${BTRFS_MOUNT}" 2>/dev/null || true
echo -e "${GREEN}  ✓ /nix synced to @nix${RESET}"

# ---------- Completion -------------------------------------------------------
echo ""
echo -e "${GREEN}${BOLD}============================================================${RESET}"
echo -e "${GREEN}${BOLD}  ✓ Migration to stateless complete!${RESET}"
echo -e "${GREEN}${BOLD}============================================================${RESET}"
echo ""
echo -e "${BOLD}Next steps:${RESET}"
echo "  1. Reboot to activate the stateless (impermanence) filesystem:"
echo "       sudo reboot"
echo ""
echo "  2. After reboot, / will be a fresh tmpfs on every boot."
echo "     /nix and /persistent survive reboots. Everything else is ephemeral."
echo ""
echo -e "${BOLD}Default login credentials after reboot:${RESET}"
echo -e "  Username: ${CYAN}nimda${RESET}"
if $CUSTOM_PASSWORD_SET; then
  echo -e "  Password: ${CYAN}(your chosen password)${RESET}"
else
  echo -e "  Password: ${CYAN}vexos (default)${RESET}"
fi
echo ""
echo -e "${YELLOW}Note: Passwords changed at runtime do NOT persist across reboots.${RESET}"
echo -e "${YELLOW}      The password resets to the configured value on every boot (by design).${RESET}"
if ! $CUSTOM_PASSWORD_SET; then
  echo -e "${YELLOW}      To set a custom password, re-run scripts/migrate-to-stateless.sh.${RESET}"
fi
echo ""
echo -e "${YELLOW}Note: After rebooting into stateless mode, the original / data on${RESET}"
echo -e "${YELLOW}the Btrfs partition remains but is not mounted. You can reclaim${RESET}"
echo -e "${YELLOW}that space later by booting from a live ISO and deleting the root${RESET}"
echo -e "${YELLOW}subvolume contents (keep only @nix and @persist).${RESET}"
echo ""
printf "Reboot now? [y/N] "
read -r REBOOT_CHOICE </dev/tty
case "${REBOOT_CHOICE,,}" in
  y|yes)
    echo "Rebooting..."
    reboot
    ;;
  *)
    echo ""
    echo -e "${YELLOW}Run 'sudo reboot' when ready.${RESET}"
    echo ""
    ;;
esac
