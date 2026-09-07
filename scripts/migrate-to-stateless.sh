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

# Clean up the install-time swap mount on exit (including on error) — see
# activation right before the nixos-rebuild boot section below. Best-effort:
# guards against a failed/interrupted run leaving swap active or the mount
# busy for a re-run.
cleanup() {
  swapoff "${BTRFS_MOUNT}/@persist/swapfile" 2>/dev/null || true
  umount "${BTRFS_MOUNT}" 2>/dev/null || true
}
trap cleanup EXIT

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

# ---------- Resolve one commit for this run (for the shared progress lib) ----
# Normally inherited from install.sh, which resolves and exports VEXOS_REV
# before handing off here. Resolve it ourselves for a direct `curl | bash` run
# so the lib fetch below is pinned to one commit rather than a moving main.
if [ -z "${VEXOS_REV:-}" ]; then
  if command -v git >/dev/null 2>&1; then
    _REV_GIT="git"
  else
    _REV_GIT="$(nix --extra-experimental-features 'nix-command flakes' \
      build nixpkgs#git --no-link --print-out-paths)/bin/git"
  fi
  VEXOS_REV="$("$_REV_GIT" ls-remote https://github.com/VictoryTek/vexos-nix main | cut -f1)"
fi

# ---------- Shared full-screen build-progress UI ----------------------------
# render_header / run_live_build + the brand-logo progress screen live in
# scripts/lib/progress.sh (shared with install.sh and stateless-setup.sh) so
# all three installers draw the identical screen. Fetched pinned to this run's
# commit; on any load failure the fallbacks below run the build with plain
# streaming output. Keep this loader block in sync across the three scripts.
# shellcheck disable=SC2034  # read by render_header in the sourced lib/progress.sh
VEXOS_INSTALLER_TITLE="VexOS Stateless Migration"
_load_progress_lib() {
  local local_lib src
  local_lib="$(dirname "$0")/lib/progress.sh"
  if [ -f "$local_lib" ]; then
    src="$(cat "$local_lib")"
  else
    src="$(curl -fsSL "https://raw.githubusercontent.com/VictoryTek/vexos-nix/${VEXOS_REV}/scripts/lib/progress.sh" 2>/dev/null || true)"
  fi
  [ -n "$src" ] && printf '%s' "$src" | grep -q 'run_live_build()' || return 1
  source /dev/stdin <<<"$src"
}
if ! _load_progress_lib; then
  echo -e "${YELLOW}Warning: could not load lib/progress.sh — falling back to plain output.${RESET}" >&2
  render_header() { :; }
  run_live_build() {
    local t="$1"; shift
    echo -e "${BOLD}${t}${RESET}"
    BUILD_LOG_PATH="$(mktemp "${TMPDIR:-/tmp}/vexos-build.XXXXXX.log")"
    "$@" 2>&1 | tee "$BUILD_LOG_PATH"
    return "${PIPESTATUS[0]}"
  }
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

# ---------- Detect the primary user account ----------------------------------
# Adopt whatever account is actually UID 1000 rather than assuming "nimda" —
# the user may have renamed it during their original NixOS install. Falls back
# to "nimda" (today's hardcoded default) if no UID 1000 account exists.
DETECTED_USER=$(getent passwd 1000 | cut -d: -f1 || true)
if [ -z "$DETECTED_USER" ]; then
  DETECTED_USER="nimda"
fi
echo -e "${BOLD}Detected primary user account: ${CYAN}${DETECTED_USER}${RESET}"
echo ""

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

# ---------- NVIDIA driver branch -------------------------------------------
NVIDIA_SUFFIX=""
if [ "$VARIANT" = "nvidia" ]; then
  echo ""
  echo -e "${BOLD}Select NVIDIA driver branch:${RESET}"
  echo "  1) Latest     — RTX, GTX 16xx, GTX 750 and newer"
  echo "  2) Legacy 580 — Maxwell/Pascal/Volta (580.x, required)"
  echo ""
  echo -e "${YELLOW}Not sure? Check: https://www.nvidia.com/en-us/drivers/unix/legacy-gpu/${RESET}"
  echo -e "${YELLOW}Wrong choice? Run this script again and switch.${RESET}"
  echo ""
  while true; do
    printf "Enter choice [1-2]: "
    read -r INPUT </dev/tty
    case "${INPUT}" in
      1) NVIDIA_SUFFIX="";           break ;;
      2) NVIDIA_SUFFIX="-legacy580"; break ;;
      *) echo -e "${RED}Invalid selection '${INPUT}'. Choose 1 or 2.${RESET}" ;;
    esac
  done
fi

# ---------- VM hypervisor selection -----------------------------------------
# QEMU/KVM and VirtualBox need different guest packages, and VirtualBox pins
# the kernel to 6.18 LTS to keep its guest additions building. "qemu" is the
# vexos.vm.platform default, so only VirtualBox writes /etc/nixos/features.nix.
VM_PLATFORM=""
if [ "$VARIANT" = "vm" ]; then
  echo ""
  echo -e "${BOLD}Select your hypervisor:${RESET}"
  echo "  1) QEMU/KVM  — Proxmox, libvirt, plain QEMU (guest agent + SPICE)"
  echo "  2) VirtualBox — Guest Additions, shared folders (pins kernel 6.18 LTS)"
  echo ""
  while [ -z "$VM_PLATFORM" ]; do
    printf "Enter choice [1-2] or name (qemu / virtualbox): "
    read -r INPUT </dev/tty
    case "${INPUT,,}" in
      1|qemu|kvm|proxmox) VM_PLATFORM="qemu"       ;;
      2|virtualbox|vbox)  VM_PLATFORM="virtualbox" ;;
      *)
        echo -e "${RED}Invalid selection '${INPUT}'. Please enter 1, 2, qemu, or virtualbox.${RESET}"
        ;;
    esac
  done
fi

# ---------- Preserve existing user password -----------------------------------
# Read the current shadow hash so the pre-migration password carries forward
# into the stateless build.  The stateless role uses users.mutableUsers = false,
# which means /etc/shadow is regenerated from the Nix config on every activation.
# Capturing the existing hash and writing it to stateless-user-override.nix
# (persisted to @persist/etc/nixos/) preserves the password across reboots,
# matching the behaviour of all other vexos roles.
HASHED_PW=""
CUSTOM_PASSWORD_SET=false

echo ""
echo -e "${BOLD}Preserving existing ${DETECTED_USER} login password...${RESET}"
EXISTING_HASH=$(getent shadow "$DETECTED_USER" 2>/dev/null | cut -d: -f2 || true)
# A valid yescrypt/SHA-512 hash starts with $ — "!" or "*" means locked/unset.
if [[ "${EXISTING_HASH}" == '$'* ]]; then
  HASHED_PW="${EXISTING_HASH}"
  CUSTOM_PASSWORD_SET=true
  echo -e "${GREEN}  ✓ Password hash found — your existing password will work after reboot.${RESET}"
else
  echo -e "${YELLOW}  No password hash for ${DETECTED_USER} found in /etc/shadow (locked or no password set).${RESET}"
  echo -e "${BOLD}  Please set a new login password for the stateless installation:${RESET}"
  # Stock NixOS installs do not include openssl in PATH; fetch it from the
  # binary cache when missing (same pattern as the git bootstrap in install.sh).
  if command -v openssl &>/dev/null; then
    OPENSSL="openssl"
  else
    echo -e "${CYAN}  openssl not found on this system — fetching from nixpkgs binary cache...${RESET}"
    OPENSSL="$(nix --extra-experimental-features 'nix-command flakes' \
      build nixpkgs#openssl.bin --no-link --print-out-paths)/bin/openssl"
  fi
  while true; do
    printf "  New password (hidden): "
    read -rs PW </dev/tty
    echo ""
    if [ -z "$PW" ]; then
      echo -e "${RED}  Password cannot be empty. Please set a password.${RESET}"
      continue
    fi
    printf "  Confirm password:  "
    read -rs PW2 </dev/tty
    echo ""
    if [ "$PW" = "$PW2" ]; then
      HASHED_PW=$(printf '%s' "$PW" | "$OPENSSL" passwd -6 -stdin)
      echo -e "${GREEN}  ✓ Password accepted.${RESET}"
      break
    else
      echo -e "${RED}  Passwords do not match. Try again.${RESET}"
    fi
  done
fi

if [ -n "$HASHED_PW" ]; then
  echo ""
  echo -e "${BOLD}Writing /etc/nixos/stateless-user-override.nix...${RESET}"
  # vexos.user.name is only written when it differs from the compiled-in
  # default ("nimda") — no need for a no-op override otherwise.
  USER_NAME_OVERRIDE=""
  if [ "$DETECTED_USER" != "nimda" ]; then
    USER_NAME_OVERRIDE="  vexos.user.name = \"${DETECTED_USER}\";"
  fi
  tee /etc/nixos/stateless-user-override.nix > /dev/null << NIXEOF
{ lib, ... }: {
${USER_NAME_OVERRIDE}
  users.users.${DETECTED_USER}.hashedPassword = lib.mkOverride 50 "${HASHED_PW}";
}
NIXEOF
  # tee writes with the invoking process's umask (0644 by default) — tighten
  # to root-only since this file carries a crackable password hash.
  chmod 0600 /etc/nixos/stateless-user-override.nix
  echo -e "${GREEN}  ✓ /etc/nixos/stateless-user-override.nix written.${RESET}"
fi

# ---------- Write vm-platform.nix (VirtualBox guests only) ----------------
# "qemu" is the vexos.vm.platform default, so a QEMU/Proxmox guest needs no
# file. git add is a no-op when /etc/nixos is not a git checkout. Kept separate
# from features.nix — the stateless role does not declare the desktop
# feature-toggle options.
if [ "$VM_PLATFORM" = "virtualbox" ]; then
  echo ""
  echo -e "${BOLD}Writing /etc/nixos/vm-platform.nix (vexos.vm.platform = virtualbox)...${RESET}"
  tee /etc/nixos/vm-platform.nix > /dev/null << 'VMPLATFORMEOF'
# /etc/nixos/vm-platform.nix
# Hypervisor selector for this stateless VM guest. Written by
# migrate-to-stateless.sh when VirtualBox is chosen.
{
  vexos.vm.platform = "virtualbox";
}
VMPLATFORMEOF
  git -C /etc/nixos add vm-platform.nix 2>/dev/null || true
  echo -e "${GREEN}  ✓ /etc/nixos/vm-platform.nix written.${RESET}"
fi

# ---------- Activate temporary install-time swap -----------------------------
# nixos-rebuild boot (below) builds the entire target closure on whatever swap
# the currently-running system already has — which may be none on a fresh
# test VM, and a from-source build under memory pressure can OOM regardless of
# the VM's RAM. @persist was just created above, so mount it again and swap on
# a file there (same path/size modules/impermanence.nix expects for the
# installed system), using the same Btrfs-aware creation NixOS's own swap
# module uses. Released by the cleanup() trap and again explicitly below,
# before the later independent re-mount of this volume for the /nix sync step.
echo ""
echo -e "${BOLD}Activating temporary swap for the build (8 GiB on @persist)...${RESET}"
mkdir -p "${BTRFS_MOUNT}"
mount -o subvolid=5 "${ROOT_DEV_RAW}" "${BTRFS_MOUNT}" 2>/dev/null || \
  mount "${ROOT_DEV_RAW}" "${BTRFS_MOUNT}"
btrfs filesystem mkswapfile --size 8192M --uuid clear "${BTRFS_MOUNT}/@persist/swapfile"
swapon "${BTRFS_MOUNT}/@persist/swapfile"
echo -e "${GREEN}  ✓ Temporary build-time swap active.${RESET}"

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
render_header
if run_live_build "Building vexos-stateless-${VARIANT}${NVIDIA_SUFFIX}..." \
     nixos-rebuild boot --flake "/etc/nixos#vexos-stateless-${VARIANT}${NVIDIA_SUFFIX}"; then
  echo -e "${GREEN}  ✓ Build complete — new generation registered for next boot.${RESET}"
  # Release the build-time swap/mount now — the /nix sync section below
  # re-mounts this same volume independently and must not find it busy.
  swapoff "${BTRFS_MOUNT}/@persist/swapfile" 2>/dev/null || true
  umount "${BTRFS_MOUNT}"
else
  echo ""
  echo -e "${RED}${BOLD}✗ nixos-rebuild boot failed.${RESET}"
  echo "  Last 60 lines of the build log (${BUILD_LOG_PATH}):"
  echo ""
  tail -n 60 "${BUILD_LOG_PATH}" 2>/dev/null || true
  echo ""
  echo -e "${RED}Migration incomplete — fix the error above and re-run this script.${RESET}"
  exit 1
fi

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
cp -p /etc/nixos/stateless-user-override.nix "${BTRFS_MOUNT}/@persist/etc/nixos/" 2>/dev/null && \
  echo -e "  ${GREEN}✓ stateless-user-override.nix persisted${RESET}" || true
cp /etc/nixos/vm-platform.nix "${BTRFS_MOUNT}/@persist/etc/nixos/" 2>/dev/null && \
  echo -e "  ${GREEN}✓ vm-platform.nix persisted${RESET}" || true
printf '%s' "vexos-stateless-${VARIANT}${NVIDIA_SUFFIX}" > "${BTRFS_MOUNT}/@persist/etc/nixos/vexos-variant"
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
echo -e "${BOLD}Login credentials after reboot:${RESET}"
echo -e "  Username: ${CYAN}${DETECTED_USER}${RESET}"
if $CUSTOM_PASSWORD_SET; then
  echo -e "  Password: ${CYAN}(same as before migration)${RESET}"
else
  echo -e "  Password: ${CYAN}(the new password you just set)${RESET}"
fi
echo ""
echo -e "${YELLOW}Note: Passwords changed at runtime do NOT persist across reboots.${RESET}"
echo -e "${YELLOW}      To update the persistent password, edit stateless-user-override.nix${RESET}"
echo -e "${YELLOW}      in /persistent/etc/nixos/ and rebuild: just rebuild${RESET}"
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
