#!/usr/bin/env bash
# =============================================================================
# stateless-setup.sh — VexOS Stateless Role Initial Disk Setup
# Repository: https://github.com/VictoryTek/vexos-nix
#
# Usage (one-liner from NixOS live ISO, recommended):
#   curl -fsSL https://raw.githubusercontent.com/VictoryTek/vexos-nix/main/scripts/stateless-setup.sh | bash
#
# Or clone first and run locally:
#   bash scripts/stateless-setup.sh
#
# What this script does:
#   1. Partitions and formats the target disk (DESTRUCTIVE — all data erased)
#   2. Creates: EFI partition (512 MiB), Btrfs root partition with subvolumes
#      (@nix → /nix,  @persist → /persistent)  — no LUKS encryption
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
  read -r DISK_INPUT </dev/tty
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
  read -r INPUT </dev/tty
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

# ---------- NVIDIA driver branch -------------------------------------------
NVIDIA_SUFFIX=""
if [ "$VARIANT" = "nvidia" ]; then
  echo ""
  echo -e "${BOLD}Select NVIDIA driver branch:${RESET}"
  echo "  1) Latest     — RTX, GTX 16xx, GTX 750 and newer"
  echo "  2) Legacy 535 — Maxwell/Pascal/Volta (LTS 535.x)"
  echo ""
  echo -e "${YELLOW}Not sure? Check: https://www.nvidia.com/en-us/drivers/unix/legacy-gpu/${RESET}"
  echo -e "${YELLOW}Wrong choice? Run this script again and switch.${RESET}"
  echo ""
  while true; do
    printf "Enter choice [1-2]: "
    read -r INPUT </dev/tty
    case "${INPUT}" in
      1) NVIDIA_SUFFIX="";           break ;;
      2) NVIDIA_SUFFIX="-legacy535"; break ;;
      *) echo -e "${RED}Invalid selection '${INPUT}'. Choose 1 or 2.${RESET}" ;;
    esac
  done
fi

# ---------- ASUS ROG/TUF hardware ------------------------------------------
ASUS_ENABLE=false
ASUS_LAPTOP=false
if [ "$VARIANT" != "vm" ]; then
  echo ""
  echo -e "${BOLD}Is this an ASUS ROG/TUF device?${RESET}"
  echo "  Laptop: enables asusd (fan curves, charge limit), supergfxctl, power-profiles-daemon"
  echo "  Desktop: enables OpenRGB for ASUS Aura motherboard RGB control"
  echo ""
  printf "ASUS ROG/TUF device? [y/N] "
  read -r INPUT </dev/tty
  case "${INPUT,,}" in
    y|yes) ASUS_ENABLE=true ;;
    *)     ASUS_ENABLE=false ;;
  esac

  if [ "$ASUS_ENABLE" = "true" ]; then
    echo ""
    printf "Is this device a laptop? [y/N] "
    read -r INPUT </dev/tty
    case "${INPUT,,}" in
      y|yes) ASUS_LAPTOP=true ;;
      *)     ASUS_LAPTOP=false ;;
    esac
  fi
fi

# ---------- Prompt: nimda user password (required) --------------------------
# A locked-account hash ("!") is the compiled-in default in configuration-stateless.nix.
# This script MUST always write stateless-user-override.nix with a real hash
# so the user can actually log in after the first boot.
HASHED_PW=""

# The live ISO does not ship openssl in PATH; fetch it from the binary cache
# when missing and use the absolute store path (same pattern as the git
# bootstrap in install.sh).
if command -v openssl &>/dev/null; then
  OPENSSL="openssl"
else
  echo -e "${CYAN}openssl not found on this system — fetching from nixpkgs binary cache...${RESET}"
  OPENSSL="$(nix --extra-experimental-features 'nix-command flakes' \
    build nixpkgs#openssl.bin --no-link --print-out-paths)/bin/openssl"
fi

echo ""
echo -e "${BOLD}Set a login password for the nimda user (required):${RESET}"
echo -e "${YELLOW}  This password is written to /etc/nixos/stateless-user-override.nix.${RESET}"
echo -e "${YELLOW}  The password is re-applied from config on every reboot (no runtime persistence).${RESET}"
echo ""
while true; do
  printf "  Password (hidden): "
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

# ---------- Hostname (auto-set, same as all other roles) --------------------
HOSTNAME="vexos"

# ---------- LUKS: always disabled -------------------------------------------
# VexOS stateless role does not use disk encryption.
# Encryption is the responsibility of the hypervisor or physical security policy.
LUKS_BOOL="false"

# ---------- Summary and final confirmation ----------------------------------
echo ""
echo -e "${BOLD}Installation summary:${RESET}"
echo "  Disk:       ${DISK}"
echo "  GPU variant: ${VARIANT}${NVIDIA_SUFFIX}"
echo "  Hostname:   ${HOSTNAME}"
echo "  LUKS:       disabled (no encryption)"
echo "  Flake target: vexos-stateless-${VARIANT}${NVIDIA_SUFFIX}"
echo ""
printf "Proceed with installation? This will ERASE ${DISK}. [y/N] "
read -r PROCEED </dev/tty
case "${PROCEED,,}" in
  y|yes) ;;
  *)
    echo "Aborting."
    exit 0
    ;;
esac

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
  --yes-wipe-all-disks \
  "${DISKO_TMP}" \
  --arg disk "\"${DISK}\"" \
  --arg enableLuks "${LUKS_BOOL}"

echo ""
echo -e "${GREEN}${BOLD}✓ Disk formatted and mounted at /mnt.${RESET}"

# ---------- Generate hardware configuration ---------------------------------
echo ""
echo -e "${BOLD}Generating hardware configuration...${RESET}"
sudo nixos-generate-config --no-filesystems --root /mnt

# Wait for udev to process disko's partition events before querying UUIDs.
# Ensures the partlabel symlinks (/dev/disk/by-partlabel/disk-main-*) exist.
udevadm settle --timeout=30

# Use sudo blkid -p to get UUIDs:
# - sudo:  the nixos live ISO user is not in the disk group, so direct block device
#          reads require root (EACCES otherwise, silently swallowed by 2>/dev/null).
# - -p:    disko calls udevadm settle BEFORE mkfs.vfat; vfat writes no kernel uevent,
#          so the blkid cache has no entry for the freshly-formatted ESP. -p bypasses
#          the stale cache and reads the UUID directly from the BPB on disk.
BOOT_UUID=$(sudo blkid -p -s UUID -o value /dev/disk/by-partlabel/disk-main-ESP 2>/dev/null || true)
ROOT_UUID=$(sudo blkid -p -s UUID -o value /dev/disk/by-partlabel/disk-main-data 2>/dev/null || true)

if [ -z "$BOOT_UUID" ]; then
  echo -e "${RED}ERROR: Could not read UUID for EFI partition (disk-main-ESP).${RESET}"
  echo "  Verify the partition exists: sudo blkid /dev/disk/by-partlabel/disk-main-ESP"
  exit 1
fi
if [ -z "$ROOT_UUID" ]; then
  echo -e "${RED}ERROR: Could not read UUID for root partition (disk-main-data).${RESET}"
  echo "  Verify the partition exists: sudo blkid /dev/disk/by-partlabel/disk-main-data"
  exit 1
fi

# Append stateless filesystem declarations with neededForBoot = true.
# nixos-generate-config --no-filesystems omits fileSystems entries entirely.
# We inject them here with UUID-based device paths and neededForBoot = true —
# the same pattern used by scripts/migrate-to-stateless.sh for existing installs.
# neededForBoot = true is required by modules/impermanence.nix; without it the
# impermanence assertions abort the build.
TMPFILE=$(mktemp)
perl -0777 -pe 's/\n\}\s*$/\n/' /mnt/etc/nixos/hardware-configuration.nix > "${TMPFILE}" 2>/dev/null || \
  head -n -1 /mnt/etc/nixos/hardware-configuration.nix > "${TMPFILE}"

cat >> "${TMPFILE}" << NIXEOF

  # ── Stateless filesystem layout ─────────────────────────────────────────
  # Written by scripts/stateless-setup.sh.
  # neededForBoot = true is required by modules/impermanence.nix.

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

sudo cp "${TMPFILE}" /mnt/etc/nixos/hardware-configuration.nix
rm -f "${TMPFILE}"
echo -e "${GREEN}✓ hardware-configuration.nix generated at /mnt/etc/nixos/hardware-configuration.nix${RESET}"

# Set hostname in hardware config could be done in the flake; skip here.

# ---------- Download template flake -----------------------------------------
echo ""
echo -e "${BOLD}Downloading vexos-nix template flake to /mnt/etc/nixos/...${RESET}"
sudo curl -fsSL "${TEMPLATE_URL}" -o /mnt/etc/nixos/flake.nix
echo -e "${GREEN}✓ /mnt/etc/nixos/flake.nix downloaded.${RESET}"

# ---------- ASUS hardware patch ---------------------------------------------
if [ "$ASUS_ENABLE" = "true" ]; then
  if grep -qF 'hardwareModule = { ... }: { };' /mnt/etc/nixos/flake.nix 2>/dev/null; then
    echo ""
    if [ "$ASUS_LAPTOP" = "true" ]; then
      echo -e "${BOLD}Patching flake.nix to enable ASUS ROG/TUF laptop support...${RESET}"
      sudo sed -i 's/hardwareModule = { \.\.\. }: { };/hardwareModule = { ... }: { vexos.hardware.asus.enable = true; vexos.hardware.asus.batteryChargeLimit = 80; };/' /mnt/etc/nixos/flake.nix
      echo -e "  ${GREEN}✓ ASUS laptop support enabled (battery charge limit set to 80%).${RESET}"
    else
      echo -e "${BOLD}Patching flake.nix to enable OpenRGB for ASUS desktop...${RESET}"
      sudo sed -i 's/hardwareModule = { \.\.\. }: { };/hardwareModule = { ... }: { programs.openrgb.enable = true; };/' /mnt/etc/nixos/flake.nix
      echo -e "  ${GREEN}✓ OpenRGB enabled for ASUS desktop Aura RGB control.${RESET}"
    fi
  else
    echo ""
    echo -e "  ${YELLOW}⚠ hardwareModule not found in flake.nix — skipping ASUS patch.${RESET}"
    echo "    To enable ASUS support manually, add to /etc/nixos/flake.nix:"
    if [ "$ASUS_LAPTOP" = "true" ]; then
      echo "      vexos.hardware.asus.enable = true;"
      echo "      vexos.hardware.asus.batteryChargeLimit = 80;"
    else
      echo "      programs.openrgb.enable = true;"
    fi
  fi
fi

# ---------- Write stateless-user-override.nix (always required) -------------
echo ""
echo -e "${BOLD}Writing stateless-user-override.nix with password hash...${RESET}"
sudo tee /mnt/etc/nixos/stateless-user-override.nix > /dev/null << NIXEOF
{ lib, ... }: {
  users.users.nimda.hashedPassword = lib.mkOverride 50 "${HASHED_PW}";
}
NIXEOF
echo -e "${GREEN}  ✓ /mnt/etc/nixos/stateless-user-override.nix written.${RESET}"

# ---------- Git-track the flake so Nix uses git+file: not path:+narHash ------
# Without git tracking, `nixos-install` locks /mnt/etc/nixos as a path: flake
# with a narHash.  Writing the lock file then changes the directory content,
# which causes a Nix assertion failure (narHash mismatch).  Initialising a git
# repo and staging all files makes Nix use git+file: instead, which is stable.
# The .git directory is also persisted so that post-boot `vexos-update` can use
# git+file:///etc/nixos URIs — keeping secrets/ out of the world-readable Nix store.
echo ""
echo -e "${BOLD}Initialising git repo in /mnt/etc/nixos to stabilise flake identity...${RESET}"
# NOTE: hardware-configuration.nix and the override .nix files MUST be
# git-tracked — the template flake imports them from the flake source, and
# git+file:// copies only tracked files into the store. Only secrets/ (read
# outside the flake source) stays untracked.
sudo tee /mnt/etc/nixos/.gitignore > /dev/null << 'GITIGNORE'
secrets/
*.bak
vexos-variant
GITIGNORE
sudo git -C /mnt/etc/nixos init -q
sudo git -C /mnt/etc/nixos add .

# ---------- Refresh flake inputs ----------------------------------------------
# Always resolve vexos-nix to the latest HEAD before installing.
# Without this, nixos-install creates a fresh flake.lock using whatever commit
# GitHub's CDN happens to serve for the main branch — which may be a stale
# cached revision if the branch was recently updated.  A stale commit can carry
# bugs that have already been fixed in the current HEAD (e.g. the broken
# lib.mkForce placement in modules/stateless-disk.nix that existed at c238ce6).
echo ""
echo -e "${CYAN}Refreshing flake inputs...${RESET}"
sudo nix --extra-experimental-features "nix-command flakes" \
  flake update --flake git+file:///mnt/etc/nixos

# ---------- Run nixos-install ------------------------------------------------
FLAKE_TARGET="vexos-stateless-${VARIANT}${NVIDIA_SUFFIX}"
echo ""
echo -e "${BOLD}Running nixos-install targeting ${CYAN}${FLAKE_TARGET}${RESET}${BOLD}...${RESET}"
echo -e "${YELLOW}This may take a while — it will download and build the NixOS closure.${RESET}"
echo ""
sudo nixos-install \
  --no-root-passwd \
  --flake "/mnt/etc/nixos#${FLAKE_TARGET}"

# ---------- Persist nixos config to /persistent -----------------------------
# /mnt/etc/nixos is on the ephemeral tmpfs root and will be wiped on first
# reboot.  Copy the thin flake and hardware config to the @persist subvolume
# so they are available via the /etc/nixos bind mount on every future boot
# (see modules/impermanence.nix — /etc/nixos is in the persistence list).
echo ""
echo -e "${BOLD}Persisting NixOS config files to /persistent...${RESET}"
sudo mkdir -p /mnt/persistent/etc/nixos
sudo cp /mnt/etc/nixos/hardware-configuration.nix /mnt/persistent/etc/nixos/ 2>/dev/null || true
sudo cp /mnt/etc/nixos/flake.nix /mnt/persistent/etc/nixos/ 2>/dev/null || true
sudo cp /mnt/etc/nixos/flake.lock /mnt/persistent/etc/nixos/ 2>/dev/null || true
sudo cp /mnt/etc/nixos/.gitignore /mnt/persistent/etc/nixos/ 2>/dev/null || true
sudo cp /mnt/etc/nixos/stateless-user-override.nix /mnt/persistent/etc/nixos/ 2>/dev/null || true
printf '%s' "vexos-stateless-${VARIANT}${NVIDIA_SUFFIX}" | sudo tee /mnt/persistent/etc/nixos/vexos-variant > /dev/null
# Persist the git repo so post-boot git+file:///etc/nixos URIs work and secrets stay out of the Nix store.
sudo cp -r /mnt/etc/nixos/.git /mnt/persistent/etc/nixos/
echo -e "${GREEN}✓ NixOS config files persisted.${RESET}"

echo ""
echo -e "${GREEN}${BOLD}============================================================${RESET}"
echo -e "${GREEN}${BOLD}  ✓ VexOS Stateless installation complete!${RESET}"
echo -e "${GREEN}${BOLD}============================================================${RESET}"
echo ""
echo -e "${BOLD}Next steps:${RESET}"
echo "  1. Remove the live ISO from your boot device."
echo "  2. Reboot: sudo reboot"
echo ""
echo -e "${BOLD}Default login credentials:${RESET}"
echo -e "  Username: ${CYAN}nimda${RESET}"
echo -e "  Password: ${CYAN}(your chosen password)${RESET}"
echo ""
echo -e "${YELLOW}Note: Passwords changed at runtime do NOT persist across reboots.${RESET}"
echo -e "${YELLOW}      The password resets to the configured value on every boot (by design).${RESET}"
echo ""
printf "Reboot now? [y/N] "
read -r REBOOT_CHOICE </dev/tty
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
