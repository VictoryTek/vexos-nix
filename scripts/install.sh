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
  echo "  Enables: asusd (RGB, fan curves, charge limit), supergfxctl, power-profiles-daemon"
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

# Headless server cannot be activated live: doing so stops display-manager.service
# during switch-to-configuration, killing the live ISO's GNOME session (and this
# script). Use `nixos-rebuild boot` to install the new generation as default
# without runtime activation; user reboots into the new system.
REBUILD_ACTION="switch"
if [ "$ROLE" = "headless-server" ]; then
  REBUILD_ACTION="boot"
fi

# ---------- Build & switch ---------------------------------------------------
echo ""
echo -e "${BOLD}Building ${CYAN}${FLAKE_TARGET}${RESET}${BOLD} (action: ${REBUILD_ACTION})...${RESET}"
if [ "$REBUILD_ACTION" = "boot" ]; then
  echo -e "${YELLOW}[headless-server] Using 'nixos-rebuild boot' to preserve the live GNOME session. The new system will not activate until you reboot.${RESET}"
fi
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

# ---------- ASUS hardware patch ---------------------------------------------
if [ "$ASUS_ENABLE" = "true" ]; then
  if grep -qF 'hardwareModule = { ... }: { };' /etc/nixos/flake.nix 2>/dev/null; then
    echo ""
    echo "  Patching /etc/nixos/flake.nix to enable ASUS ROG/TUF support..."
    if [ "$ASUS_LAPTOP" = "true" ]; then
      sudo sed -i 's/hardwareModule = { \.\.\. }: { };/hardwareModule = { ... }: { vexos.hardware.asus.enable = true; vexos.hardware.asus.batteryChargeLimit = 80; };/' /etc/nixos/flake.nix
      echo -e "  ${GREEN}✓ ASUS hardware support enabled (laptop — battery charge limit set to 80%).${RESET}"
    else
      sudo sed -i 's/hardwareModule = { \.\.\. }: { };/hardwareModule = { ... }: { vexos.hardware.asus.enable = true; };/' /etc/nixos/flake.nix
      echo -e "  ${GREEN}✓ ASUS hardware support enabled.${RESET}"
    fi
    echo ""
  else
    echo ""
    echo -e "  ${YELLOW}⚠ hardwareModule not found in /etc/nixos/flake.nix — skipping ASUS patch.${RESET}"
    echo "    To enable ASUS support manually, add to your /etc/nixos/flake.nix:"
    echo "      vexos.hardware.asus.enable = true;"
    if [ "$ASUS_LAPTOP" = "true" ]; then
      echo "      vexos.hardware.asus.batteryChargeLimit = 80;"
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
# The current installer uses nixpkgs rollback instead of LTS kernel override;
# any leftover file forces the wrong kernel and must not enter the git index.
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
for f in flake.nix hardware-configuration.nix stateless-user-override.nix; do
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

# 'nixpkgs.follows = "vexos-nix/nixpkgs"' in the template is advisory.
# nix flake update may still resolve follows to the latest nixos-25.11 branch
# HEAD rather than the specific commit pinned in vexos-nix's flake.lock, leaving
# the user with a newer (potentially uncached) nixpkgs.  Fetch vexos-nix's
# committed flake.lock and force nixpkgs to its exact revision so the dry-build
# uses only packages that are already in the binary cache.
_VEXOS_NIXPKGS_REV=$(curl -fsSL --max-time 10 \
  "https://raw.githubusercontent.com/VictoryTek/vexos-nix/main/flake.lock" \
  2>/dev/null | jq -r '.nodes.nixpkgs.locked.rev' 2>/dev/null || true)
if [ -n "$_VEXOS_NIXPKGS_REV" ]; then
  sudo nix --extra-experimental-features 'nix-command flakes' \
    flake lock /etc/nixos \
    --override-input nixpkgs "github:NixOS/nixpkgs/${_VEXOS_NIXPKGS_REV}" 2>/dev/null || true
fi

# Stage the (now-pinned) lock file so all subsequent git+file:// evaluations see it.
sudo "$GIT" -C /etc/nixos add flake.lock

# ---------- Cache-query helper -----------------------------------------------
# Walks recent nixpkgs history (via GitHub API) to find the most recent nixpkgs
# revision where a given Nix attribute's outPath is present in cache.nixos.org.
# $1 = Nix attribute to evaluate (e.g., linuxPackages_latest.nvidiaPackages.stable)
# $2 = optional GitHub path filter to scope the commit query
# Returns the full nixpkgs rev string, or nothing if none found within 5 commits.
find_cached_nixpkgs_for_attr() {
  local nix_attr="${1}"
  local path_filter="${2:-}"

  local current_rev
  current_rev=$(jq -r '.nodes.nixpkgs.locked.rev' /etc/nixos/flake.lock 2>/dev/null) || return 0
  [ -z "$current_rev" ] && return 0

  local api_url="https://api.github.com/repos/NixOS/nixpkgs/commits?per_page=5&sha=${current_rev}"
  [ -n "$path_filter" ] && api_url="${api_url}&path=${path_filter}"

  local commits_json
  commits_json=$(curl -fsSL --max-time 15 "$api_url" 2>/dev/null) || return 0

  local revs
  revs=$(printf '%s' "$commits_json" | jq -r '.[].sha' 2>/dev/null) || return 0
  [ -z "$revs" ] && return 0

  for rev in $revs; do
    local out_path
    # builtins.fetchTarball without sha256 is valid under --impure.
    out_path=$(sudo nix --extra-experimental-features 'nix-command flakes' \
      eval --raw --impure --expr \
      "(import (builtins.fetchTarball \"https://github.com/NixOS/nixpkgs/archive/${rev}.tar.gz\") { system = \"x86_64-linux\"; config.allowUnfree = true; config.nvidia.acceptLicense = true; }).${nix_attr}.outPath" \
      2>/dev/null) || continue
    [ -z "$out_path" ] && continue
    if nix --extra-experimental-features 'nix-command flakes' \
       path-info --store https://cache.nixos.org "$out_path" &>/dev/null 2>&1; then
      echo "$rev"
      return 0
    fi
  done
  # Nothing found — return 0; caller checks for empty output.
}

# ---------- Build & switch ---------------------------------------------------
# Cache check: dry-build first to see what would need to be compiled locally.
# Filters out NixOS system-level derivations that are always built locally and
# take under a second (activation scripts, unit files, bootloader, initrd, etc.)
# If any real packages (C++, Rust, Electron, ...) are missing from the binary
# cache the install aborts cleanly so you can retry once cache.nixos.org catches up.
echo ""
echo -e "${CYAN}Checking binary cache for all required packages...${RESET}"
DRY_OUT=$(sudo nixos-rebuild dry-build --flake "git+file:///etc/nixos#${FLAKE_TARGET}" 2>&1 || true)
# Extract the "will be built" section and keep only versioned package derivations
# (e.g. gnome-shell-49.4.drv, steam-1.0.0.85.drv). Config-assembly derivations
# (PAM files, AppArmor rules, systemd units, Home Manager links, etc.) are always
# rebuilt locally — they contain machine-specific data and are never in the binary
# cache — but they complete in milliseconds and should not block the install.
SOURCE_BUILDS=$(printf '%s\n' "$DRY_OUT" \
  | awk '/will be built:/{p=1;next} /will be fetched:|^building |^[^ \t]/{p=0} p && /\/nix\/store\//{sub(/.*\/nix\/store\/[a-z0-9]+-/,""); print}' \
  | grep -E -- '-[0-9]+\.[0-9]+' \
  | grep -Ev '^(nixos-system-|system-units|etc-nixos|unit-|activation-script|specialisation-|install-bootloader|loader-|grub-|extlinux-|initrd|linux-[0-9]|kernel|stage-[12]-|crate-|cargo-vendor|perl-[0-9]|lua-[0-9]|python3?-[0-9]|up-[0-9]|zvariant|zbus|gtk4-|glib-|gio-|gdk-|pango-|graphene-|cairo-|gettext-rs|gettext-sys|serde_yml|libyml|system-deps|cfg-expr|winnow|endi-|enumflags|version-compare|zbus_names|zbus_macros|zvariant_|ureq|uds_windows|env_filter|env_logger|utf8-zero|glib-build-tools|glib-macros|glib-sys|gobject-sys|gio-sys|pango-sys|gdk-pixbuf-sys|graphene-sys|cairo-sys|cairo-rs|gdk-pixbuf-|mpv-with-scripts|plex-desktop|ibus-with-plugins|retroarch-with-cores|steam|steam-unwrapped|discord|podman-docker-compat|nodejs-|vscode-|claude-code-|code-[0-9]|VSCode_|umu-launcher|.*-init\.|.*-bwrap\.|.*-fhsenv)' \
  || true)

if [ -n "$SOURCE_BUILDS" ]; then
  # Kernel-dependent packages (NVIDIA driver, OpenRazer DKMS) miss cache when
  # nixpkgs recently bumped the kernel or a driver and Hydra hasn't built them yet.
  # When all cache misses are kernel-dependent, search nixpkgs history for the most
  # recent revision where the relevant packages ARE cached, then temporarily roll back
  # nixpkgs to that rev.  At that rev, linuxPackages_latest resolves to the most
  # recent cached kernel — not the LTS fallback.
  HEAVY_BUILD_REGEX='^(NVIDIA-Linux-|nvidia-x11-|nvidia-settings-|openrazer-[0-9])'
  NON_KERNEL_BUILDS=$(printf '%s\n' "$SOURCE_BUILDS" | grep -Ev "$HEAVY_BUILD_REGEX" || true)

  if [ -z "$NON_KERNEL_BUILDS" ]; then
    echo ""
    echo -e "${YELLOW}${BOLD}⚠ Target kernel packages are not yet in the binary cache:${RESET}"
    printf '%s\n' "$SOURCE_BUILDS" | sed 's/^/    /'
    echo ""
    echo -e "${CYAN}Searching nixpkgs history for the most recent cached versions...${RESET}"

    # Select which nixpkgs attribute to check.  For NVIDIA, checking nvidiaPackages
    # implicitly validates the kernel too — if the driver is cached, it was built
    # against a cached kernel.  For all others, check the kernel directly.
    if [ "$VARIANT" = "nvidia" ] && [ "$NVIDIA_SUFFIX" = "" ]; then
      CHECK_ATTR="linuxPackages_latest.nvidiaPackages.stable"
      CHECK_PATH="pkgs/os-specific/linux/nvidia-x11/default.nix"
    elif [ "$VARIANT" = "nvidia" ] && [ "$NVIDIA_SUFFIX" = "-legacy535" ]; then
      CHECK_ATTR="linuxPackages_latest.nvidiaPackages.legacy_535"
      CHECK_PATH="pkgs/os-specific/linux/nvidia-x11/default.nix"
    else
      CHECK_ATTR="linuxPackages_latest.kernel"
      CHECK_PATH="pkgs/os-specific/linux/kernel/"
    fi

    FOUND_REV=$(find_cached_nixpkgs_for_attr "$CHECK_ATTR" "$CHECK_PATH")

    if [ -n "$FOUND_REV" ]; then
      short_rev="${FOUND_REV:0:8}"
      echo ""
      echo -e "${CYAN}✓ Found cached packages at nixpkgs ${short_rev}."
      echo -e "Temporarily using this nixpkgs pin for first install."
      echo -e "The latest versions will be applied automatically when you run 'just update'"
      echo -e "or use the Up app, once cache.nixos.org has built them (typically 1-3 days).${RESET}"
      echo ""

      FLAKE_LOCK_BACKUP=$(cat /etc/nixos/flake.lock)

      # Roll back nixpkgs in flake.lock to the found rev.
      # At that rev linuxPackages_latest resolves to a cached kernel version —
      # no kernel-install-override.nix needed.
      sudo nix --extra-experimental-features 'nix-command flakes' \
        flake lock /etc/nixos \
        --override-input nixpkgs "github:NixOS/nixpkgs/${FOUND_REV}" 2>/dev/null
      sudo "$GIT" -C /etc/nixos add flake.lock

      echo -e "${CYAN}Verifying cached nixpkgs resolves all cache misses...${RESET}"
      DRY_OUT2=$(sudo nixos-rebuild dry-build --flake "git+file:///etc/nixos#${FLAKE_TARGET}" 2>&1 || true)
      REMAINING=$(printf '%s\n' "$DRY_OUT2" \
        | awk '/will be built:/{p=1;next} /will be fetched:|^building |^[^ \t]/{p=0} p && /\/nix\/store\//{sub(/.*\/nix\/store\/[a-z0-9]+-/,""); print}' \
        | grep -E -- '-[0-9]+\.[0-9]+' \
        | grep -Ev '^(nixos-system-|system-units|etc-nixos|unit-|activation-script|specialisation-|install-bootloader|loader-|grub-|extlinux-|initrd|linux-[0-9]|kernel|stage-[12]-|crate-|cargo-vendor|perl-[0-9]|lua-[0-9]|python3?-[0-9]|up-[0-9]|zvariant|zbus|gtk4-|glib-|gio-|gdk-|pango-|graphene-|cairo-|gettext-rs|gettext-sys|serde_yml|libyml|system-deps|cfg-expr|winnow|endi-|enumflags|version-compare|zbus_names|zbus_macros|zvariant_|ureq|uds_windows|env_filter|env_logger|utf8-zero|glib-build-tools|glib-macros|glib-sys|gobject-sys|gio-sys|pango-sys|gdk-pixbuf-sys|graphene-sys|cairo-sys|cairo-rs|gdk-pixbuf-|mpv-with-scripts|plex-desktop|ibus-with-plugins|retroarch-with-cores|steam|steam-unwrapped|discord|podman-docker-compat|nodejs-|vscode-|claude-code-|code-[0-9]|VSCode_|umu-launcher|.*-init\.|.*-bwrap\.|.*-fhsenv)' \
        || true)

      if [ -n "$REMAINING" ]; then
        printf '%s' "$FLAKE_LOCK_BACKUP" | sudo tee /etc/nixos/flake.lock > /dev/null
        sudo "$GIT" -C /etc/nixos add flake.lock
        echo ""
        echo -e "${YELLOW}${BOLD}⚠ Additional packages are not yet in the binary cache and would need to"
        echo -e "  be compiled from source (this can take hours):${RESET}"
        echo ""
        printf '%s\n' "$REMAINING" | sed 's/^/    /'
        echo ""
        echo -e "${YELLOW}The install has been aborted. cache.nixos.org usually builds new"
        echo -e "packages within 24 hours. Run the install script again once they are cached."
        echo ""
        echo -e "To install now anyway (accepts local source builds), run:${RESET}"
        echo "  sudo nixos-rebuild ${REBUILD_ACTION} --flake /etc/nixos#${FLAKE_TARGET}"
        echo ""
        exit 1
      fi
      echo -e "${GREEN}✓ All packages available in binary cache (nixpkgs pin ${short_rev}).${RESET}"

    else
      # No cached version found in recent nixpkgs history — last resort: build from source.
      echo ""
      echo -e "${YELLOW}${BOLD}⚠ No cached packages found in recent nixpkgs history.${RESET}"
      echo ""
      echo -e "${YELLOW}This happens when nixpkgs recently bumped multiple packages and"
      echo -e "cache.nixos.org has not yet built any recent versions (typically 1-3 days).${RESET}"
      echo ""
      echo -e "${BOLD}Options:${RESET}"
      echo "  1) Build from source — kernel modules compile locally (~30-60 min)"
      echo "  2) Abort             — wait for cache.nixos.org and re-run the installer"
      echo ""
      printf "Build from source now? [y/N] "
      read -r BUILD_CHOICE </dev/tty
      case "${BUILD_CHOICE,,}" in
        y|yes)
          echo ""
          echo -e "${CYAN}Proceeding with local source builds (target kernel and packages)."
          echo -e "This will take approximately 30-60 minutes. Do not interrupt the build.${RESET}"
          echo ""
          ;;
        *)
          echo ""
          echo -e "${YELLOW}Install aborted. Run the installer again once cache.nixos.org has built"
          echo -e "the packages, or run:${RESET}"
          echo "  sudo nixos-rebuild ${REBUILD_ACTION} --flake /etc/nixos#${FLAKE_TARGET}"
          echo ""
          exit 1
          ;;
      esac
    fi

  else
    # Non-kernel packages require a local build — cannot help with a kernel swap.
    echo ""
    echo -e "${YELLOW}${BOLD}⚠ Some packages are not yet in the binary cache and would need to"
    echo -e "  be compiled from source (this can take hours):${RESET}"
    echo ""
    printf '%s\n' "$SOURCE_BUILDS" | sed 's/^/    /'
    echo ""
    echo -e "${YELLOW}The install has been aborted. cache.nixos.org usually builds new"
    echo -e "packages within 24 hours. Run the install script again once they are cached."
    echo ""
    echo -e "To install now anyway (accepts local source builds), run:${RESET}"
    echo "  sudo nixos-rebuild ${REBUILD_ACTION} --flake /etc/nixos#${FLAKE_TARGET}"
    echo ""
    exit 1
  fi
else
  echo -e "${GREEN}✓ All packages available in binary cache.${RESET}"
fi
echo ""

if sudo nixos-rebuild "${REBUILD_ACTION}" --flake "git+file:///etc/nixos#${FLAKE_TARGET}"; then
  echo ""
  if [ "$REBUILD_ACTION" = "boot" ]; then
    echo -e "${GREEN}${BOLD}✓ Build complete. New generation registered as default.${RESET}"
    echo -e "${YELLOW}[headless-server] Build complete. Reboot now to start the headless server. The live ISO will remain active until you do.${RESET}"
    echo ""
    printf "Reboot now? [Y/n] "
    read -r REBOOT_CHOICE </dev/tty
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
    echo -e "${GREEN}${BOLD}✓ Build and switch successful!${RESET}"
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
  fi
else
  echo ""
  echo -e "${RED}${BOLD}✗ nixos-rebuild ${REBUILD_ACTION} failed. Reboot skipped.${RESET}"
  echo "  Review the output above for errors and retry:"
  echo "    sudo nixos-rebuild ${REBUILD_ACTION} --flake /etc/nixos#${FLAKE_TARGET}"
  echo ""
  exit 1
fi
