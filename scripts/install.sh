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
echo -e "${BOLD}Select your role:${RESET}"
echo "  1) Desktop  — Full gaming / workstation stack"
echo "  2) Stateless — Minimal build (no gaming / dev / virt / ASUS)"
echo "  3) HTPC    — Home theatre PC"
echo "  4) Server  — Server (GUI or Headless)"
echo "  5) Vanilla  — Stock NixOS baseline (system restore)"
echo ""

ROLE=""
while [ -z "$ROLE" ]; do
  printf "Enter choice [1-5] or name (desktop / stateless / htpc / server / vanilla): "
  read -r INPUT </dev/tty
  case "${INPUT,,}" in
    1|desktop)  ROLE="desktop"  ;;
    2|stateless) ROLE="stateless" ;;
    3|htpc)     ROLE="htpc"     ;;
    4|server)   ROLE="server"   ;;
    5|vanilla)  ROLE="vanilla"  ;;
    *)
      echo -e "${RED}Invalid selection '${INPUT}'. Choose 1-5 or a role name.${RESET}"
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
if [ "$ROLE" = "desktop" ] || [ "$ROLE" = "htpc" ] || [ "$ROLE" = "server" ] || [ "$ROLE" = "headless-server" ] || [ "$ROLE" = "stateless" ] || [ "$ROLE" = "vanilla" ]; then
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
# Vanilla always uses the kernel nouveau driver — no proprietary driver branches.
NVIDIA_SUFFIX=""
if [ "$VARIANT" = "nvidia" ]; then
  echo ""
  echo -e "${BOLD}Select NVIDIA driver branch:${RESET}"
  echo "  1) Latest     — RTX, GTX 16xx, GTX 750 and newer"
  echo "  2) Legacy 535 — Maxwell/Pascal/Volta (LTS 535.x)"
  echo ""
  echo -e "${YELLOW}Not sure? Check: https://www.nvidia.com/en-us/drivers/unix/legacy-gpu/${RESET}"
  echo -e "${YELLOW}Wrong choice? Run this installer again and switch.${RESET}"
  echo ""

  while true; do
    printf "Enter choice [1-2]: "
    read -r INPUT </dev/tty
    case "${INPUT}" in
      1) NVIDIA_SUFFIX="";           break ;;
      2) NVIDIA_SUFFIX="-legacy535"; break ;;
      *)
        echo -e "${RED}Invalid selection '${INPUT}'. Choose 1 or 2.${RESET}"
        ;;
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

FLAKE_TARGET="vexos-${ROLE}-${VARIANT}${NVIDIA_SUFFIX}"

# Always use 'boot' instead of 'switch': nixos-rebuild switch restarts
# display-manager.service during switch-to-configuration, which kills the live ISO's
# GNOME session and logs the user out. Using 'boot' installs the new generation as
# default without runtime activation; the user reboots into the new system.
REBUILD_ACTION="boot"

# ---------- Build & switch ---------------------------------------------------
echo ""
echo -e "${BOLD}Building ${CYAN}${FLAKE_TARGET}${RESET}${BOLD} (action: ${REBUILD_ACTION})...${RESET}"
echo -e "${YELLOW}Using 'nixos-rebuild boot' to preserve the live session. The new system will not activate until you reboot.${RESET}"
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
echo ""
echo -e "${CYAN}Refreshing flake inputs...${RESET}"
sudo nix --extra-experimental-features "nix-command flakes" \
  flake update --flake git+file:///etc/nixos

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
echo ""
echo -e "${CYAN}Checking what will be fetched vs built locally...${RESET}"
DRY_OUT=$(sudo nixos-rebuild dry-build --flake "git+file:///etc/nixos#${FLAKE_TARGET}" 2>&1 || true)
SOURCE_BUILDS=$(printf '%s\n' "$DRY_OUT" \
  | awk '/will be built:/{p=1;next} /will be fetched:|^building |^[^ \t]/{p=0} p && /\/nix\/store\//{sub(/.*\/nix\/store\/[a-z0-9]+-/,""); print}' \
  | grep -E -- '-[0-9]+\.[0-9]+' \
  || true)

if [ -n "$SOURCE_BUILDS" ]; then
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
echo ""

if sudo nixos-rebuild "${REBUILD_ACTION}" --flake "git+file:///etc/nixos#${FLAKE_TARGET}"; then
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
  printf "Reboot now? [Y/n] "
  read -r REBOOT_CHOICE </dev/tty
  REBOOT_CHOICE="${REBOOT_CHOICE%$'\r'}"
  case "${REBOOT_CHOICE,,}" in
    n|no)
      echo -e "${YELLOW}Reboot skipped. Run 'systemctl reboot' when ready.${RESET}"
      ;;
    *)
      echo "Rebooting..."
      systemctl reboot
      ;;
  esac
else
  echo ""
  echo -e "${RED}${BOLD}✗ nixos-rebuild ${REBUILD_ACTION} failed. Reboot skipped.${RESET}"
  echo "  Review the output above for errors and retry:"
  echo "    sudo nixos-rebuild ${REBUILD_ACTION} --flake /etc/nixos#${FLAKE_TARGET}"
  echo ""
  exit 1
fi
