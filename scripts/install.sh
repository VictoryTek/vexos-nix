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
# Unattended (no prompts, no TTY needed): answer every question with flags and add
# --yes. `bash scripts/install.sh --help` lists them; through curl, pass them after `bash -s --`:
#   curl -fsSL .../scripts/install.sh | bash -s -- --role desktop --gpu amd --yes
#
# This is the only command needed, on either of two starting points:
#   - An already-installed NixOS system: if /etc/nixos/flake.nix is missing
#     the script downloads the wrapper (template/etc-nixos-flake.nix) itself,
#     using the existing /etc/nixos/hardware-configuration.nix.
#   - A NixOS live ISO on a blank disk: detected automatically, hands off to
#     scripts/bare-metal-install.sh (disko-based, any role — see that script).
#
# Supported roles (expand this list as new roles are added to the flake):
#   desktop         — Gaming/workstation (AMD, NVIDIA, Intel, VM); choice of
#                     GNOME/COSMIC/Hyprland desktop environment
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
# this, install.sh handing off to bare-metal-install.sh/migrate-to-stateless.sh via
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

# ---------- Shared libs ------------------------------------------------------
# Colours, the full-screen build-progress UI (lib/progress.sh) and the prompts
# (lib/prompts.sh: gum arrow-key UI with plain read fallbacks) are shared with
# bare-metal-install.sh and migrate-to-stateless.sh, so they live in scripts/lib/
# and are pulled in through lib/bootstrap.sh. Only this stub is duplicated: it
# has to run before anything can be fetched.
# shellcheck disable=SC2034  # read by the sourced libs
VEXOS_INSTALLER_TITLE="VexOS Interactive Installer"
# shellcheck disable=SC2034  # read by the sourced libs
VEXOS_PROMPT_STYLE="full"
# _load_lib NAME — source scripts/lib/NAME from the local checkout when run as
# `bash scripts/install.sh`, otherwise fetch it pinned to this run's commit (same
# mechanism as every other file this script pulls). Returns 1 on failure.
_load_lib() {
  local local_lib src
  local_lib="$(dirname "$0")/lib/$1"
  if [ -f "$local_lib" ]; then
    src="$(cat "$local_lib")"
  else
    src="$(curl -fsSL "https://raw.githubusercontent.com/VictoryTek/vexos-nix/${VEXOS_REV}/scripts/lib/$1" 2>/dev/null || true)"
  fi
  [ -n "$src" ] || return 1
  source /dev/stdin <<<"$src"
}
_load_lib bootstrap.sh || { echo "error: could not load scripts/lib/bootstrap.sh (pinned to ${VEXOS_REV})." >&2; exit 1; }
# Answer flags / --yes for an unattended run (see --help); exported so the
# stateless hand-off scripts inherit them.
parse_answer_flags "$@"
init_gum

# ---------- Flake wrapper ----------------------------------------------------
# /etc/nixos/flake.nix is the thin wrapper (template/etc-nixos-flake.nix) that
# pulls this repo's config. Fetched only when absent, so re-running the installer
# to switch role/variant keeps the existing wrapper (and any edits to it).
# Downloaded to a temp file first so a truncated download can never leave a
# partial flake.nix that the "already exists" check would trust on the next run.
#
# An existing wrapper from before the side-file layout (inline bootloaderModule /
# hardwareModule / hostModule blocks) is upgraded in place by
# scripts/upgrade-wrapper.sh — a no-op for a current wrapper. Without that, the
# side-files written below (bootloader.nix, hardware-local.nix, host.nix) would
# be silently ignored.
ensure_flake_wrapper() {
  if [ -f /etc/nixos/flake.nix ]; then
    if [ -f "$(dirname "$0")/upgrade-wrapper.sh" ]; then
      bash "$(dirname "$0")/upgrade-wrapper.sh"
    else
      curl -fsSL "https://raw.githubusercontent.com/VictoryTek/vexos-nix/${VEXOS_REV}/scripts/upgrade-wrapper.sh" | bash
    fi
    return 0
  fi
  local tmp
  tmp="$(mktemp "${TMPDIR:-/tmp}/vexos-flake.XXXXXX")"
  echo -e "${CYAN}No /etc/nixos/flake.nix found — downloading the vexos-nix flake wrapper...${RESET}"
  if ! curl -fsSL -o "$tmp" \
       "https://raw.githubusercontent.com/VictoryTek/vexos-nix/${VEXOS_REV}/template/etc-nixos-flake.nix"; then
    rm -f "$tmp"
    echo -e "${RED}✗ Could not download the flake wrapper.${RESET}" >&2
    exit 1
  fi
  sudo install -D -m 644 "$tmp" /etc/nixos/flake.nix
  rm -f "$tmp"
  echo -e "${GREEN}✓ /etc/nixos/flake.nix installed.${RESET}"
}

# ---------- Header -----------------------------------------------------------
render_header
echo -e "${YELLOW}Source: ${SCRIPT_URL}${RESET}"
echo -e "${YELLOW}Verify: https://github.com/VictoryTek/vexos-nix/blob/${VEXOS_REV}/scripts/install.sh${RESET}"
echo ""

# ---------- Role selection ---------------------------------------------------
ask_choice ROLE "Select your role" "" "" \
  "desktop:Desktop  — Full gaming / workstation stack" \
  "stateless:Stateless — Minimal build (no gaming / dev / virt / ASUS)" \
  "htpc:HTPC    — Home theatre PC" \
  "server:Server  — Server (GUI or Headless)" \
  "vanilla:Vanilla  — Stock NixOS baseline (system restore)"

# ---------- Server sub-type selection ----------------------------------------
if [ "$ROLE" = "server" ]; then
  ask_choice SERVER_TYPE "Select server type" "" "" \
    "headless:Headless Server — CLI only, no desktop environment" \
    "gui:GUI Server      — GNOME desktop environment"

  if [ "$SERVER_TYPE" = "headless" ]; then
    ROLE="headless-server"
  fi
fi

# ---------- Desktop environment selection (desktop role only) ----------------
DESKTOP_ENV="gnome"
if [ "$ROLE" = "desktop" ]; then
  ask_choice DESKTOP_ENV "Select desktop environment" "gnome" "" \
    "gnome:GNOME    — Full-featured, most tested (default)" \
    "cosmic:COSMIC   — System76's new Rust-based desktop" \
    "hyprland:Hyprland — Tiling Wayland compositor + DankMaterialShell"
fi

# ---------- Live-ISO / existing-system detection -----------------------------
# Generalized: this used to be computed only inside the stateless branch below,
# reachable only for that one role. Every role can now be installed bare-metal
# from a live ISO (scripts/bare-metal-install.sh), so it's computed once, up
# front, for all of them.
ROOT_FSTYPE=$(findmnt -n -o FSTYPE / 2>/dev/null || true)
LIVE_ISO=false
if [ "$ROOT_FSTYPE" = "tmpfs" ]; then
  # Distinguish a genuine live ISO (tmpfs root, no /nix mount) from an
  # already-running stateless (impermanence) system, which also has a tmpfs
  # root by design (tmpfs root + /nix mounted on btrfs subvol @nix).
  NIX_FSTYPE=$(findmnt -n -o FSTYPE /nix 2>/dev/null || true)
  if [ "$NIX_FSTYPE" != "btrfs" ]; then
    LIVE_ISO=true
  fi
fi

# ---------- Stateless-only: switch variant in place, or migrate an existing --
# ---------- (non-live-ISO) install ------------------------------------------
# Fresh bare-metal installs (live ISO, any role) are handled uniformly further
# below — this block only covers the two outcomes that are specific to the
# stateless role and don't apply to any other role.
if [ "$ROLE" = "stateless" ] && ! $LIVE_ISO; then
  if [ "$ROOT_FSTYPE" = "tmpfs" ]; then
    # Already running a stateless (impermanence) system — just rebuild with new variant.
    # Fall through to GPU selection and nixos-rebuild switch below.
    echo ""
    echo -e "${CYAN}Stateless system detected — will switch variant via nixos-rebuild.${RESET}"
  else
    # Running on an existing NixOS install — in-place Btrfs migration
    echo ""
    echo -e "${CYAN}Existing install detected — launching in-place stateless migration...${RESET}"
    echo ""
    # migrate-to-stateless.sh persists /etc/nixos/flake.nix into @persist and
    # builds from it, so the wrapper must exist before the hand-off.
    ensure_flake_wrapper
    # sudo resets the environment by default, so plain `export` above would not
    # reach this child — pass VEXOS_REV, and any answers given as flags, explicitly
    # on the sudo command line.
    _sudo_env=(VEXOS_REV="${VEXOS_REV}")
    for _n in VEXOS_YES "${!VEXOS_ANSWER_@}"; do
      [ -n "${!_n+x}" ] && _sudo_env+=("${_n}=${!_n}")
    done
    curl -fsSL "https://raw.githubusercontent.com/VictoryTek/vexos-nix/${VEXOS_REV}/scripts/migrate-to-stateless.sh" | sudo "${_sudo_env[@]}" bash
    exit 0
  fi
fi

# ---------- GPU variant selection --------------------------------------------
# Shared by both paths below (live-ISO bare-metal install, and the
# already-installed nixos-rebuild path) — asked once, uniformly, regardless of
# which one this run turns out to be.
VARIANT=""
if [ "$ROLE" = "desktop" ] || [ "$ROLE" = "htpc" ] || [ "$ROLE" = "server" ] || [ "$ROLE" = "headless-server" ] || [ "$ROLE" = "stateless" ] || [ "$ROLE" = "vanilla" ]; then
  ask_gpu_variant
fi

# ---------- VM hypervisor selection ------------------------------------------
# See ask_vm_platform (lib/prompts.sh) for why this is asked up front.
VM_PLATFORM=""
if [ "$VARIANT" = "vm" ]; then
  ask_vm_platform
fi

# ---------- NVIDIA driver branch selection -----------------------------------
# Vanilla always uses the kernel nouveau driver — no proprietary driver branches.
NVIDIA_SUFFIX=""
if [ "$VARIANT" = "nvidia" ]; then
  ask_nvidia_branch
fi

# ---------- ASUS ROG/TUF hardware ------------------------------------------
ASUS_ENABLE=false
ASUS_LAPTOP=false
if [ "$VARIANT" != "vm" ]; then
  ask_asus
fi

# ---------- Live-ISO bare-metal install (any role) ---------------------------
# Every role gets a disko-based bare-metal install now, not just stateless —
# hand off the GPU/NVIDIA/VM/ASUS/desktop-environment answers already
# collected above so bare-metal-install.sh doesn't ask them again.
if $LIVE_ISO; then
  echo ""
  echo -e "${CYAN}Live ISO detected — launching bare-metal install (erases target disk)...${RESET}"
  echo ""
  _sudo_env=(
    VEXOS_REV="${VEXOS_REV}"
    ROLE="${ROLE}"
    DESKTOP_ENV="${DESKTOP_ENV}"
    VARIANT="${VARIANT}"
    NVIDIA_SUFFIX="${NVIDIA_SUFFIX}"
    VM_PLATFORM="${VM_PLATFORM}"
    ASUS_ENABLE="${ASUS_ENABLE}"
    ASUS_LAPTOP="${ASUS_LAPTOP}"
    # Tells bare-metal-install.sh every question above was already asked here
    # (including ones whose answer is a plain default, e.g. DESKTOP_ENV=gnome)
    # — don't re-ask any of them.
    VEXOS_ANSWERS_PROVIDED=1
  )
  for _n in VEXOS_YES "${!VEXOS_ANSWER_@}"; do
    [ -n "${!_n+x}" ] && _sudo_env+=("${_n}=${!_n}")
  done
  curl -fsSL "https://raw.githubusercontent.com/VictoryTek/vexos-nix/${VEXOS_REV}/scripts/bare-metal-install.sh" \
    | sudo "${_sudo_env[@]}" bash
  exit 0
fi

FLAKE_TARGET="vexos-${ROLE}-${VARIANT}${NVIDIA_SUFFIX}"

# ---------- Binary caches for the install build ------------------------------
# The flake being built here is /etc/nixos (the thin template wrapper), and Nix
# reads nixConfig only from the TOP-LEVEL flake — an input's nixConfig is
# ignored. So this repo's own nixConfig block never applies during an install,
# and modules/nix-noctalia-cache.nix only takes effect from the second boot
# onward (it is part of the configuration being built). Without these options a
# Hyprland install compiles noctalia — a Qt/C++/Quickshell shell that is in no
# public cache except this one — entirely from source.
#
# Passed as --option rather than relying on nixConfig + --accept-flake-config so
# they apply even when /etc/nixos/flake.nix is an older template: re-running the
# installer to switch role/variant never re-downloads it. root is always a
# trusted user, so extra-substituters is honoured.
#
# Keys duplicated from flake.nix's nixConfig — this script runs standalone via
# `curl | bash` with no local checkout to source a shared fragment from, so the
# two are kept in sync manually (same situation as the UNAVOIDABLE_REGEX copy in
# pkgs/vexos-update/default.nix).
INSTALL_CACHE_OPTS=(
  --option extra-substituters
  "https://noctalia.cachix.org https://cache.saumon.network/proxmox-nixos"
  --option extra-trusted-public-keys
  "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4= proxmox-nixos:D9RYSWpQQC/msZUWphOY2I5RLH5Dd6yQcaHIuug7dWM="
)

# ---------- Temporary install swap -------------------------------------------
# ensure_install_swap (lib/swap.sh) guards creation on RAM/filesystem/free
# space — see its own comment. Unlike the stateless scripts' swapfile (which
# becomes the *installed* system's permanent swap — see their comments), this
# one is scratch space only: the installed system provisions its own separate
# swap at a different path (modules/system.nix), so this file is always
# deleted on exit.
VEXOS_INSTALL_SWAP="/var/vexos-install-swap"

cleanup_install_swap() {
  if [ "${INSTALL_SWAP_ACTIVE:-false}" = "true" ]; then
    sudo swapoff "$VEXOS_INSTALL_SWAP" 2>/dev/null || true
    sudo rm -f "$VEXOS_INSTALL_SWAP"
  fi
}
trap cleanup_install_swap EXIT

setup_install_swap() {
  ensure_install_swap "$VEXOS_INSTALL_SWAP" 4096
}

# Always use 'boot' instead of 'switch': nixos-rebuild switch restarts
# display-manager.service during switch-to-configuration, which kills the live ISO's
# GNOME session and logs the user out. Using 'boot' installs the new generation as
# default without runtime activation; the user reboots into the new system.
REBUILD_ACTION="boot"

# ---------- Build & switch ---------------------------------------------------
render_header
echo -e "${BOLD}Building ${CYAN}${FLAKE_TARGET}${RESET}${BOLD} (action: ${REBUILD_ACTION})...${RESET}"
echo -e "${YELLOW}Using 'nixos-rebuild boot' to preserve the live session. The new system will not activate until you reboot.${RESET}"
render_progress "Preparing system..." 1 3

ensure_flake_wrapper

# ---------- UEFI / BIOS preflight check -------------------------------------
# vexos-nix defaults to systemd-boot (UEFI). On Legacy BIOS machines we patch
# /etc/nixos/bootloader.nix to use GRUB before building.
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
  preset_block_device GRUB_DEVICE GRUB_DEVICE || true  # --grub-device; else prompt below
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
  echo "  Writing /etc/nixos/bootloader.nix to use GRUB on ${GRUB_DEVICE}..."
  # The wrapper imports bootloader.nix when present. Use the vexos.bootloader /
  # vexos.grub.device options so modules/system.nix owns the actual
  # boot.loader.* assignments. Vanilla never imports that module (it sets
  # systemd-boot with mkDefault), so there the GRUB options are set directly.
  if [ "$ROLE" = "vanilla" ]; then
    sudo tee /etc/nixos/bootloader.nix > /dev/null << GRUBNIX
# /etc/nixos/bootloader.nix
# Written by install.sh — legacy BIOS boot via GRUB.
{
  boot.loader.systemd-boot.enable = false;
  boot.loader.grub = {
    enable     = true;
    efiSupport = false;
    device     = "${GRUB_DEVICE}";
  };
}
GRUBNIX
  else
    sudo tee /etc/nixos/bootloader.nix > /dev/null << GRUBNIX
# /etc/nixos/bootloader.nix
# Written by install.sh — legacy BIOS boot via GRUB.
{
  vexos.bootloader  = "grub";
  vexos.grub.device = "${GRUB_DEVICE}";
}
GRUBNIX
  fi
  echo -e "  ${GREEN}✓ bootloader.nix written for GRUB (${GRUB_DEVICE}).${RESET}"
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
    EFI_DEV=""
    if preset_block_device EFI_DEV EFI_DEVICE; then  # --efi-device
      :
    elif [ -n "$GUM" ]; then
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

  # ---------- Bootloader choice (UEFI only) -----------------------------------
  # Asked up front: systemd-boot (default) or Limine.
  # Unlike systemd-boot, Limine's own menu can be made to list OSes on other
  # physical disks (see modules/boot-discovery.nix upstream); it's newer and
  # less battle-tested in nixpkgs, so it's presented as a deliberate choice,
  # not a recommendation.
  #
  # Not offered on vanilla: configuration-vanilla.nix sets
  # boot.loader.systemd-boot.enable directly and never imports
  # modules/system.nix, so vexos.bootloader (which bootloader.nix sets below)
  # isn't a declared option there — it would break evaluation.
  USE_LIMINE=false
  if [ "$ROLE" = "vanilla" ]; then
    :
  else
    ask_choice BOOTLOADER "Select your bootloader" "systemd-boot" "" \
      "systemd-boot:systemd-boot — default, simple and well tested" \
      "limine:Limine       — opt-in, can list OSes on other disks (dual-boot friendly)"
    if [ "$BOOTLOADER" = "limine" ]; then USE_LIMINE=true; fi

    if [ "$USE_LIMINE" = "true" ]; then
      echo "  Writing /etc/nixos/bootloader.nix to use Limine..."
      # Same as the GRUB case above — modules/system.nix stays the single owner
      # of the actual boot.loader.* assignments via vexos.bootloader.
      sudo tee /etc/nixos/bootloader.nix > /dev/null << 'LIMINENIX'
# /etc/nixos/bootloader.nix
# Written by install.sh — Limine instead of the default systemd-boot.
{
  vexos.bootloader = "limine";
}
LIMINENIX
      echo -e "  ${GREEN}✓ bootloader.nix written for Limine.${RESET}"
    fi
    echo ""
  fi
fi

# ---------- ASUS hardware-local.nix -----------------------------------------
# The wrapper imports hardware-local.nix when present, so this is a plain file
# write rather than a patch of flake.nix — it cannot half-succeed.
if [ "$ASUS_ENABLE" = "true" ]; then
  echo ""
  if [ "$ASUS_LAPTOP" = "true" ]; then
    echo "  Writing /etc/nixos/hardware-local.nix to enable ASUS ROG/TUF laptop support..."
    sudo tee /etc/nixos/hardware-local.nix > /dev/null << 'ASUSNIX'
# /etc/nixos/hardware-local.nix
# Written by install.sh — ASUS ROG/TUF laptop.
{
  vexos.hardware.asus.enable = true;
  vexos.hardware.asus.batteryChargeLimit = 80;
}
ASUSNIX
    echo -e "  ${GREEN}✓ ASUS laptop support enabled (battery charge limit set to 80%).${RESET}"
  else
    echo "  Writing /etc/nixos/hardware-local.nix to enable OpenRGB for ASUS desktop..."
    sudo tee /etc/nixos/hardware-local.nix > /dev/null << 'ASUSNIX'
# /etc/nixos/hardware-local.nix
# Written by install.sh — ASUS desktop (Aura RGB via OpenRGB).
{ pkgs, ... }: {
  environment.systemPackages = [ pkgs.openrgb-with-all-plugins ];
  boot.kernelModules = [ "i2c-dev" ];
  services.udev.packages = [ pkgs.openrgb-with-all-plugins ];
}
ASUSNIX
    echo -e "  ${GREEN}✓ OpenRGB enabled for ASUS desktop Aura RGB control.${RESET}"
  fi
  echo ""
fi

# ---------- ZFS hostId (host.nix) ---------------------------------------------
# host.nix carries networking.hostId — the first 8 hex characters of
# /etc/machine-id — for the server roles, where ZFS bakes it into every pool.
# Written only when absent: it must never change once pools exist. Other roles
# don't import host.nix, so nothing is written for them.
if { [ "$ROLE" = "server" ] || [ "$ROLE" = "headless-server" ]; } && [ ! -f /etc/nixos/host.nix ]; then
  HOST_ID="$(head -c 8 /etc/machine-id)"
  sudo tee /etc/nixos/host.nix > /dev/null << HOSTNIX
# /etc/nixos/host.nix
# ZFS host identity. Written once by install.sh; must not change after ZFS
# pools are created.
{
  networking.hostId = "${HOST_ID}";
}
HOSTNIX
  echo -e "  ${GREEN}✓ hostId set to ${HOST_ID} in /etc/nixos/host.nix.${RESET}"
fi

# ---------- Write host choices to /etc/nixos/features.nix ---------------------
# features_set <nix.option.path> <string-value>
# Creates features.nix if absent, replaces the option if already present
# (commented or not), appends it before the closing brace otherwise. Mirrors
# the replace-or-append sed pattern `just enable-feature` uses, so the file
# stays editable by both paths.
features_set() {
  _key="$1"
  _val="$2"
  # Escape dots for the grep/sed patterns that match the option path.
  _key_re="$(printf '%s' "$_key" | sed 's/\./\\./g')"

  if [ ! -f /etc/nixos/features.nix ]; then
    sudo tee /etc/nixos/features.nix > /dev/null << FEATURESNIX
# /etc/nixos/features.nix
# Optional feature toggles for this VexOS host.
# Managed by \`just enable-feature <feature>\` / \`just disable-feature <feature>\`.
# After editing, run \`just rebuild\` to apply.
{
  ${_key} = "${_val}";
}
FEATURESNIX
  elif grep -qP "^\s*#?\s*${_key_re}\s*=" /etc/nixos/features.nix 2>/dev/null; then
    sudo sed -i -E "s|^(\s*)#?\s*${_key_re}\s*=\s*\"[a-z-]+\"\s*;|\1${_key} = \"${_val}\";|" /etc/nixos/features.nix
  else
    sudo sed -i "\$ s|^}|  ${_key} = \"${_val}\";\n}|" /etc/nixos/features.nix
  fi
}

# features_unset <nix.option.path>
# Removes an active assignment of the option, if any. Counterpart to
# features_set: a re-run of this installer must not leave the previous run's
# answers behind (features.nix survives across runs, and also holds toggles from
# `just enable-feature` that this installer must not touch — so only the keys
# the installer itself manages are ever unset). Commented-out lines have no
# effect and are left alone. No-op when features.nix does not exist.
features_unset() {
  _key="$1"
  _key_re="$(printf '%s' "$_key" | sed 's/\./\\./g')"
  if [ -f /etc/nixos/features.nix ] \
     && grep -qE "^[[:space:]]*${_key_re}[[:space:]]*=" /etc/nixos/features.nix 2>/dev/null; then
    sudo sed -i -E "/^[[:space:]]*${_key_re}[[:space:]]*=/d" /etc/nixos/features.nix
    echo -e "  ${GREEN}✓ Removed stale ${_key} from /etc/nixos/features.nix.${RESET}"
  fi
}

# Desktop environment — only written when a non-default DE was chosen. GNOME
# stays the implicit default with no file needed, matching
# vexos.desktop.environment's own NixOS default. Every other outcome (GNOME, or
# a non-desktop role) clears any value left by a previous run: features.nix is
# imported by desktop, htpc and server, and a stale "hyprland" would evaluate
# cleanly there and silently boot a GUI role with no desktop environment.
if [ "$ROLE" = "desktop" ] && [ "$DESKTOP_ENV" != "gnome" ]; then
  render_header
  features_set "vexos.desktop.environment" "$DESKTOP_ENV"
  echo -e "  ${GREEN}✓ Desktop environment set to ${DESKTOP_ENV} in /etc/nixos/features.nix.${RESET}"
else
  features_unset "vexos.desktop.environment"
fi

# VM hypervisor — only written for VirtualBox. "qemu" is the option's own NixOS
# default, so a QEMU/Proxmox guest needs no file at all; any other outcome
# clears a VirtualBox value left by a previous run.
#
# A plain side-file, not features.nix: vexos.vm.platform is declared by
# modules/gpu/vm-guest-additions.nix, reachable from any role's `vm` variant
# (headless-server and vanilla included) — but those two roles don't import
# featuresFile, so writing it there would be silently inert for them. The
# wrapper imports vm-platform.nix uniformly for every role instead (item 12's
# fix for a pre-existing bug found while generalising the bare-metal install
# path — see template/etc-nixos-flake.nix's localFiles).
if [ "$VM_PLATFORM" = "virtualbox" ]; then
  render_header
  sudo tee /etc/nixos/vm-platform.nix > /dev/null << 'VMPLATFORMNIX'
# /etc/nixos/vm-platform.nix
# Written by install.sh — VirtualBox guest.
{
  vexos.vm.platform = "virtualbox";
}
VMPLATFORMNIX
  echo -e "  ${GREEN}✓ VM platform set to virtualbox in /etc/nixos/vm-platform.nix.${RESET}"
elif [ -f /etc/nixos/vm-platform.nix ]; then
  sudo rm -f /etc/nixos/vm-platform.nix
  echo -e "  ${GREEN}✓ Removed stale /etc/nixos/vm-platform.nix.${RESET}"
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
#   b) Re-runs of the installer where side-files (bootloader, ASUS, hostId) were
#      just written or the wrapper was upgraded but not yet re-staged —
#      git+file:// would otherwise evaluate the stale committed version,
#      ignoring them.
for f in flake.nix hardware-configuration.nix stateless-user-override.nix features.nix \
         bootloader.nix hardware-local.nix host.nix hostname.nix vm-platform.nix \
         user-override.nix; do
  if [ -f "/etc/nixos/$f" ]; then
    sudo "$GIT" -C /etc/nixos add -f "$f"
  fi
done

# ---------- Flake lock refresh -----------------------------------------------
# Always re-lock before building. A stale /etc/nixos/flake.lock from a previous
# (failed) install attempt would otherwise pin the flake to an old revision,
# potentially pulling in packages that have since been removed from the repo.
#
# vexos-nix is locked to this run's commit (VEXOS_REV) rather than to whatever
# main is at this moment — the wrapper's input has no ref, so a plain update
# would build a config that may differ from the scripts that were just run.
# The pin lives only in flake.lock (its `original` stays the unpinned URL), so a
# later `just update` / vexos-update moves to main as usual.
render_progress "Refreshing flake inputs..." 2 3
if [ -n "$GUM" ]; then
  "$GUM" spin --title "Refreshing flake inputs..." -- \
    sudo nix --extra-experimental-features "nix-command flakes" \
    flake update --flake git+file:///etc/nixos \
    --override-input vexos-nix "github:VictoryTek/vexos-nix/${VEXOS_REV}"
else
  echo -e "${CYAN}Refreshing flake inputs...${RESET}"
  sudo nix --extra-experimental-features "nix-command flakes" \
    flake update --flake git+file:///etc/nixos \
    --override-input vexos-nix "github:VictoryTek/vexos-nix/${VEXOS_REV}"
fi

# Stage the refreshed lock file so all subsequent git+file:// evaluations see it.
sudo "$GIT" -C /etc/nixos add flake.lock

# ---------- Build & switch ---------------------------------------------------
# No separate `nixos-rebuild dry-build` pass here: it costs one entire extra
# evaluation (the most expensive non-build step, ~1.7 GiB peak on a desktop
# config) purely to print the list of derivations that will be compiled locally
# — which the real build below prints itself ("these N derivations will be
# built") seconds later. NVIDIA's proprietary userspace and the patched
# OpenRazer are the expected entries on that list: both are unfree or locally
# patched, so Hydra never caches them.
#
# --max-jobs 1 matches what the installed system enforces for the same reason
# (modules/nix.nix: "Prevents OOM on low-RAM machines"). It bounds peak memory
# to one compile at a time and costs no time on a cache-hit install —
# substitutions are governed by max-substitution-jobs, not max-jobs.
render_progress "Preparing build environment..." 3 3
setup_install_swap
render_header
if run_live_build "Building ${FLAKE_TARGET}..." \
     sudo nixos-rebuild "${REBUILD_ACTION}" --flake "git+file:///etc/nixos#${FLAKE_TARGET}" \
     --max-jobs 1 "${INSTALL_CACHE_OPTS[@]}"; then
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
  if preset_yes_no REBOOT no; then  # --reboot / --no-reboot; default no when unattended
    [ "$PRESET_YN" = "yes" ] || REBOOT_NOW=false
  elif [ -n "$GUM" ]; then
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
  echo "    sudo nixos-rebuild ${REBUILD_ACTION} --flake /etc/nixos#${FLAKE_TARGET} --max-jobs 1"
  echo ""
  exit 1
fi
