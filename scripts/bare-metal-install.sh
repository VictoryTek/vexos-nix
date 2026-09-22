#!/usr/bin/env bash
# =============================================================================
# bare-metal-install.sh — VexOS Bare-Metal Install (any role, live ISO)
# Repository: https://github.com/VictoryTek/vexos-nix
#
# Usage (one-liner from NixOS live ISO, recommended):
#   curl -fsSL https://raw.githubusercontent.com/VictoryTek/vexos-nix/main/scripts/bare-metal-install.sh | bash -s -- --role desktop
#
# Or clone first and run locally:
#   bash scripts/bare-metal-install.sh --role desktop
#
# Usually invoked automatically by install.sh, which already asked the role,
# desktop-environment, GPU/NVIDIA/VM/ASUS questions and detected the live ISO —
# it exports ROLE and hands off here. Run directly (as above) for the same
# flow standalone; ROLE then comes from --role or a prompt.
#
# Requires UEFI firmware — template/disko-layout.nix only produces a GPT disk
# with an EFI System Partition, which Legacy BIOS cannot boot. For a BIOS-only
# machine, install NixOS manually with GRUB first, then run install.sh to
# switch it onto vexos-nix (that path already handles BIOS/GRUB).
#
# What this script does:
#   1. Partitions and formats the target disk (DESTRUCTIVE — all data erased),
#      or resumes a previous failed attempt on the same disk instead — see
#      "Resuming a failed attempt" below.
#   2. Creates: EFI partition (512 MiB), Btrfs root partition — with
#      @nix/@persist subvolumes for the stateless role (impermanence), or a
#      single conventional Btrfs partition mounted at "/" for every other
#      role — no LUKS encryption.
#   3. Generates hardware-configuration.nix (stateless: --no-filesystems, then
#      UUID-based fileSystems with neededForBoot = true injected manually,
#      required by modules/impermanence.nix; every other role: a plain
#      nixos-generate-config --root /mnt, which detects real fileSystems
#      entries on its own — no manual injection needed)
#   4. Downloads the vexos-nix template flake to /mnt/etc/nixos/
#   5. Runs nixos-install targeting the chosen vexos-<role>-<variant>
#
# Resuming a failed attempt:
#   If a previous run got as far as formatting the disk but nixos-install then
#   failed, re-running this script detects the existing layout and offers to
#   mount it as-is instead of wiping the disk again — for the stateless role,
#   @nix keeps whatever the failed attempt already downloaded/built. Pass
#   --wipe to force a fresh reformat instead.
#
# SECURITY NOTICE:
#   This script is fetched from raw.githubusercontent.com and executed directly.
#   Always verify the source URL above before running.
#   Source code: https://github.com/VictoryTek/vexos-nix/blob/main/scripts/bare-metal-install.sh
# =============================================================================

set -euo pipefail

# Clean up temp files on exit (including on error)
cleanup() {
  # Release whichever install-time swapfile is active (see activation below)
  # so a re-run of this script in the same live session can disko-reformat
  # the same disk without it being held busy by an active swap device.
  sudo swapoff /mnt/persistent/swapfile 2>/dev/null || true
  sudo swapoff /mnt/var/tmp/vexos-install-swap 2>/dev/null || true
}
trap cleanup EXIT

# ---------- Resolve one commit for this entire run ---------------------------
# main is a moving target, and this script's downloads (template flake, disko
# template) plus the disk-formatting/install steps that follow can span several
# minutes. Resolve the commit once so every download in this run is consistent.
# If VEXOS_REV is already set (inherited from install.sh, which resolves and
# exports it before handing off here), reuse it instead of re-resolving —
# that's what keeps the whole install.sh -> bare-metal-install.sh chain pinned
# to one commit rather than each script picking its own point-in-time HEAD.
if [ -z "${VEXOS_REV:-}" ]; then
  if command -v git >/dev/null 2>&1; then
    _REV_GIT="git"
  else
    _REV_GIT="$(nix --extra-experimental-features 'nix-command flakes' \
      build nixpkgs#git --no-link --print-out-paths)/bin/git"
  fi
  VEXOS_REV="$("$_REV_GIT" ls-remote https://github.com/VictoryTek/vexos-nix main | cut -f1)"
fi

REPO_RAW="https://raw.githubusercontent.com/VictoryTek/vexos-nix/${VEXOS_REV}"
TEMPLATE_URL="${REPO_RAW}/template/etc-nixos-flake.nix"
DISKO_TEMPLATE_URL="${REPO_RAW}/template/disko-layout.nix"
DISKO_TMP="/tmp/vexos-disko-layout.nix"

# ---------- Shared libs ------------------------------------------------------
# Colours, the full-screen build-progress UI (lib/progress.sh), the prompts
# (lib/prompts.sh) and the install-time swap guard (lib/swap.sh) are shared
# with install.sh and migrate-to-stateless.sh, so they live in scripts/lib/ and
# are pulled in through lib/bootstrap.sh. Only this stub is duplicated: it has
# to run before anything can be fetched.
# shellcheck disable=SC2034  # read by the sourced libs
VEXOS_INSTALLER_TITLE="VexOS Bare-Metal Installer"
# _load_lib NAME — source scripts/lib/NAME from the local checkout when run as
# `bash scripts/bare-metal-install.sh`, otherwise fetch it pinned to this run's
# commit (REPO_RAW, resolved above). Returns 1 on failure.
_load_lib() {
  local local_lib src
  local_lib="$(dirname "$0")/lib/$1"
  if [ -f "$local_lib" ]; then
    src="$(cat "$local_lib")"
  else
    src="$(curl -fsSL "${REPO_RAW}/scripts/lib/$1" 2>/dev/null || true)"
  fi
  [ -n "$src" ] || return 1
  source /dev/stdin <<<"$src"
}
_load_lib bootstrap.sh || { echo "error: could not load scripts/lib/bootstrap.sh (pinned to ${VEXOS_REV})." >&2; exit 1; }
# Answer flags / --yes for an unattended run (also inherited from install.sh
# through the environment); see --help.
parse_answer_flags "$@"

# ---------- Role (inherited from install.sh, or --role / prompt standalone) --
if [ -z "${ROLE:-}" ]; then
  ask_choice ROLE "Select your role" "" "" \
    "desktop:Desktop  — Full gaming / workstation stack" \
    "stateless:Stateless — Minimal build (no gaming / dev / virt / ASUS)" \
    "htpc:HTPC    — Home theatre PC" \
    "server:Server  — Server (GUI or Headless)" \
    "headless-server:Headless Server — CLI only, no desktop environment" \
    "vanilla:Vanilla  — Stock NixOS baseline (system restore)"
  if [ "$ROLE" = "server" ]; then
    ask_choice SERVER_TYPE "Select server type" "" "" \
      "headless:Headless Server — CLI only, no desktop environment" \
      "gui:GUI Server      — GNOME desktop environment"
    [ "$SERVER_TYPE" = "headless" ] && ROLE="headless-server"
  fi
fi
STATELESS=false
[ "$ROLE" = "stateless" ] && STATELESS=true

# ---------- Header -----------------------------------------------------------
echo ""
echo -e "${BOLD}${CYAN}============================================================${RESET}"
echo -e "${BOLD}${CYAN}   VexOS Bare-Metal Install — ${ROLE}${RESET}"
echo -e "${BOLD}${CYAN}============================================================${RESET}"
echo ""
echo -e "${RED}${BOLD}  WARNING: This script will ERASE ALL DATA on the target disk.${RESET}"
echo -e "${YELLOW}  Run this from the NixOS live ISO, NOT on an existing system.${RESET}"
echo ""

# ---------- UEFI check --------------------------------------------------------
# template/disko-layout.nix always produces a GPT disk with an EFI System
# Partition — there is no BIOS/MBR variant. Booting that from BIOS/Legacy
# firmware is not possible, and disko/nixos-install have no way to detect this
# for us (they'd happily "succeed" and produce an unbootable disk). Fail fast
# with a clear message instead — install.sh's own BIOS/GRUB handling only
# applies to an *already-installed* system, which this isn't yet.
if [ ! -d /sys/firmware/efi ]; then
  echo -e "${RED}${BOLD}✗ This machine booted in Legacy BIOS mode.${RESET}"
  echo "  The bare-metal install path only supports UEFI systems."
  echo "  Boot the live ISO in UEFI mode instead (check your firmware settings),"
  echo "  or install NixOS manually with GRUB and then run install.sh to switch"
  echo "  it onto vexos-nix."
  exit 1
fi

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
preset_block_device DISK DISK || true  # --disk; else prompt below
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

# ---------- Prompts: desktop env (desktop role only), GPU, NVIDIA branch, ----
# ---------- hypervisor, ASUS -------------------------------------------------
# Shared with the other installers via lib/prompts.sh. gum is best-effort; it
# is initialised here, after the nix-command/flakes check above, so the fetch
# works.
#
# VEXOS_ANSWERS_PROVIDED is set by install.sh's hand-off: it already asked
# every question below (DESKTOP_ENV included, even when the answer is just
# its default "gnome"), so none of them are re-asked here. Unset when this
# script runs standalone (directly from a live ISO by URL, per its own usage
# comment) — then it asks all of them itself, same as before this role became
# selectable at all.
init_gum

DESKTOP_ENV="${DESKTOP_ENV:-gnome}"
if [ "$ROLE" = "desktop" ] && [ -z "${VEXOS_ANSWERS_PROVIDED:-}" ]; then
  ask_choice DESKTOP_ENV "Select desktop environment" "gnome" "" \
    "gnome:GNOME    — Full-featured, most tested (default)" \
    "cosmic:COSMIC   — System76's new Rust-based desktop" \
    "hyprland:Hyprland — Tiling Wayland compositor + DankMaterialShell"
fi

VARIANT="${VARIANT:-}"
if [ -z "$VARIANT" ] && [ -z "${VEXOS_ANSWERS_PROVIDED:-}" ]; then
  ask_gpu_variant
fi

NVIDIA_SUFFIX="${NVIDIA_SUFFIX:-}"
if [ "$VARIANT" = "nvidia" ] && [ -z "${VEXOS_ANSWERS_PROVIDED:-}" ]; then
  ask_nvidia_branch
fi

# "qemu" is the vexos.vm.platform default, so only VirtualBox writes
# /etc/nixos/vm-platform.nix (see below).
VM_PLATFORM="${VM_PLATFORM:-}"
if [ "$VARIANT" = "vm" ] && [ -z "${VEXOS_ANSWERS_PROVIDED:-}" ]; then
  ask_vm_platform
fi

ASUS_ENABLE="${ASUS_ENABLE:-false}"
ASUS_LAPTOP="${ASUS_LAPTOP:-false}"
if [ "$VARIANT" != "vm" ] && [ -z "${VEXOS_ANSWERS_PROVIDED:-}" ]; then
  ask_asus
fi

# ---------- Prompt: nimda user password (required for a usable install) -----
# modules/users.nix declares nimda with no hashedPassword/initialPassword at
# all, and nixos-install does not prompt for non-root account passwords — an
# undeclared password defaults to locked. Without this, a fresh install of
# ANY role would boot into an account nobody can log into. The stateless role
# additionally locks the account by default and asserts against it
# (configuration-stateless.nix), so this was already required there; every
# other role needs it just as much for a *usable* result, even without an
# assertion forcing the point.
HASHED_PW=""
echo ""
echo -e "${BOLD}Set a login password for the nimda user (required):${RESET}"
if $STATELESS; then
  echo -e "${YELLOW}  This password is written to /etc/nixos/stateless-user-override.nix.${RESET}"
  echo -e "${YELLOW}  The password is re-applied from config on every reboot (no runtime persistence).${RESET}"
else
  echo -e "${YELLOW}  This password is written to /etc/nixos/user-override.nix.${RESET}"
fi
echo ""
ask_password

# ---------- Hostname (auto-set, same as the other installers) ---------------
HOSTNAME="vexos"

# ---------- LUKS: always disabled -------------------------------------------
# No prompt for it — not something the "already installed" install.sh flow
# offers either, and the disko template already supports it structurally if
# a future need arises.
LUKS_BOOL="false"

# ---------- Check for a resumable previous attempt on this disk -------------
# A nixos-install failure after disko already formatted the disk (below) would
# otherwise mean a re-run wipes it and rebuilds the entire closure from
# nothing — including whatever the failed attempt already downloaded/built.
# Detect disko's own layout (partition labels from template/disko-layout.nix's
# disk.main.{ESP,data}) already present on the CHOSEN disk specifically, with
# the filesystem types disko would have produced — same
# btrfs-subvolume-show detection migrate-to-stateless.sh uses for @nix/@persist
# specifically, extended here to also cover the conventional single-partition
# layout (which has nothing to check beyond partition existence and fstype —
# simpler than the stateless case, not harder).
RESUME=false
_esp_part="/dev/disk/by-partlabel/disk-main-ESP"
_data_part="/dev/disk/by-partlabel/disk-main-data"
if [ -b "$_esp_part" ] && [ -b "$_data_part" ] \
   && [ "/dev/$(lsblk -no PKNAME "$_esp_part" 2>/dev/null)" = "$DISK" ] \
   && [ "/dev/$(lsblk -no PKNAME "$_data_part" 2>/dev/null)" = "$DISK" ] \
   && [ "$(lsblk -no FSTYPE "$_esp_part" 2>/dev/null)" = "vfat" ] \
   && [ "$(lsblk -no FSTYPE "$_data_part" 2>/dev/null)" = "btrfs" ]; then
  if $STATELESS; then
    _resume_check_mnt="$(mktemp -d)"
    if sudo mount -o subvolid=5 "$_data_part" "$_resume_check_mnt" 2>/dev/null; then
      if sudo btrfs subvolume show "$_resume_check_mnt/@nix" &>/dev/null \
         && sudo btrfs subvolume show "$_resume_check_mnt/@persist" &>/dev/null; then
        RESUME=true
      fi
      sudo umount "$_resume_check_mnt"
    fi
    rmdir "$_resume_check_mnt" 2>/dev/null || true
  else
    RESUME=true
  fi
fi

if $RESUME; then
  echo ""
  echo -e "${YELLOW}${BOLD}An existing VexOS layout was found on ${DISK}${RESET}"
  echo -e "${YELLOW}(a previous install attempt).${RESET}"
  echo -e "${YELLOW}Resuming reuses whatever was already downloaded/built and skips the wipe.${RESET}"
  if preset_yes_no WIPE no; then  # --wipe forces a fresh reformat; --yes alone resumes
    [ "$PRESET_YN" = "yes" ] && RESUME=false
  elif ask_yes_no "Wipe the disk and start over instead of resuming?"; then
    RESUME=false
  fi
fi

# ---------- Summary and final confirmation ----------------------------------
echo ""
echo -e "${BOLD}Installation summary:${RESET}"
echo "  Role:       ${ROLE}"
echo "  Disk:       ${DISK}"
if $RESUME; then
  echo "  Mode:       Resume — reuses the existing layout, disk not erased"
else
  echo "  Mode:       Fresh install — ${DISK} will be erased"
fi
echo "  GPU variant: ${VARIANT}${NVIDIA_SUFFIX}"
[ "$VARIANT" = "vm" ] && echo "  Hypervisor: ${VM_PLATFORM}"
[ "$ROLE" = "desktop" ] && echo "  Desktop env: ${DESKTOP_ENV}"
echo "  Hostname:   ${HOSTNAME}"
echo "  LUKS:       disabled (no encryption)"
echo "  Flake target: vexos-${ROLE}-${VARIANT}${NVIDIA_SUFFIX}"
echo ""
if preset_yes_no PROCEED yes; then  # --yes confirms; needs an explicit --disk (above)
  PROCEED="$PRESET_YN"
elif $RESUME; then
  printf "Proceed with installation? Will resume the existing layout on ${DISK}. [y/N] "
  read -r PROCEED </dev/tty
else
  printf "Proceed with installation? This will ERASE ${DISK}. [y/N] "
  read -r PROCEED </dev/tty
fi
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
DISKO_ARGS=(--mode "destroy,format,mount" --yes-wipe-all-disks)
if $RESUME; then
  echo -e "${BOLD}Resuming: mounting the existing layout on ${DISK} (not reformatting)...${RESET}"
  DISKO_ARGS=(--mode mount)
else
  echo -e "${BOLD}${RED}DESTRUCTIVE STEP: Formatting ${DISK} with disko...${RESET}"
fi
echo ""
# disko is a flake input of vexos-nix, so `--inputs-from` runs the revision
# locked in flake.lock at this run's commit (VEXOS_REV) — not whatever `latest`
# points at on the day, for a tool that wipes disks.
sudo nix \
  --extra-experimental-features 'nix-command flakes' \
  run --inputs-from "github:VictoryTek/vexos-nix/${VEXOS_REV}" disko -- \
  "${DISKO_ARGS[@]}" \
  "${DISKO_TMP}" \
  --arg disk "\"${DISK}\"" \
  --arg enableLuks "${LUKS_BOOL}" \
  --arg stateless "${STATELESS}"

echo ""
if $RESUME; then
  echo -e "${GREEN}${BOLD}✓ Existing layout mounted at /mnt.${RESET}"
else
  echo -e "${GREEN}${BOLD}✓ Disk formatted and mounted at /mnt.${RESET}"
fi

# ---------- Activate temporary install-time swap -----------------------------
# nixos-install (below) builds the entire target closure while running from
# the live ISO, which has no swap of its own — a from-source build under
# memory pressure can OOM the installer regardless of how much RAM the target
# machine/VM has.
echo ""
if $STATELESS; then
  # modules/impermanence.nix declares a persistent swapfile at
  # /persistent/swapfile for the *installed* system (auto-created there via
  # `btrfs filesystem mkswapfile` on first boot if missing), but that does
  # nothing during this install. ensure_install_swap (lib/swap.sh) creates
  # that same file now (same path/size the module expects) so the live ISO
  # has real overflow capacity for the build. Left on disk either way: if
  # created, first boot's swap activation finds a correctly-sized file
  # already in place and reuses it rather than recreating it; if skipped
  # (guard), first boot creates it itself.
  ensure_install_swap /mnt/persistent/swapfile 8192
else
  # Conventional roles: whether the installed system ends up with its own
  # persistent swapfile (modules/system.nix's vexos.swap.enable, at
  # /var/lib/swapfile) depends on the chosen role/variant — false on VM
  # guests and ZFS server roles — so predicting and pre-creating THAT file
  # isn't worth the complexity. Use a disposable scratch file instead
  # (deleted below either way), matching install.sh's own scratch-swap
  # pattern for the "already installed" flow.
  sudo mkdir -p /mnt/var/tmp
  ensure_install_swap /mnt/var/tmp/vexos-install-swap 4096
fi

# ---------- Generate hardware configuration ---------------------------------
echo ""
echo -e "${BOLD}Generating hardware configuration...${RESET}"
if $STATELESS; then
  sudo nixos-generate-config --no-filesystems --root /mnt
else
  # Conventional layout: a single mounted root + /boot is exactly what
  # nixos-generate-config expects to find and describe on its own — no
  # --no-filesystems, no manual injection needed (unlike stateless, which
  # needs the neededForBoot = true attribute nixos-generate-config doesn't
  # set). This produces a hardware-configuration.nix indistinguishable from
  # one written by a normal, already-installed host.
  sudo nixos-generate-config --root /mnt
fi

if $STATELESS; then
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
  # Written by scripts/bare-metal-install.sh.
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
fi
echo -e "${GREEN}✓ hardware-configuration.nix generated at /mnt/etc/nixos/hardware-configuration.nix${RESET}"

# ---------- Download template flake -----------------------------------------
echo ""
echo -e "${BOLD}Downloading vexos-nix template flake to /mnt/etc/nixos/...${RESET}"
sudo curl -fsSL "${TEMPLATE_URL}" -o /mnt/etc/nixos/flake.nix
echo -e "${GREEN}✓ /mnt/etc/nixos/flake.nix downloaded.${RESET}"

# ---------- ASUS hardware-local.nix -----------------------------------------
# The wrapper imports hardware-local.nix when present. Must be written before
# `git add .` below so git+file:// picks it up.
if [ "$ASUS_ENABLE" = "true" ]; then
  echo ""
  if [ "$ASUS_LAPTOP" = "true" ]; then
    echo -e "${BOLD}Writing hardware-local.nix to enable ASUS ROG/TUF laptop support...${RESET}"
    sudo tee /mnt/etc/nixos/hardware-local.nix > /dev/null << 'ASUSNIX'
# /etc/nixos/hardware-local.nix
# Written by bare-metal-install.sh — ASUS ROG/TUF laptop.
{
  vexos.hardware.asus.enable = true;
  vexos.hardware.asus.batteryChargeLimit = 80;
}
ASUSNIX
    echo -e "  ${GREEN}✓ ASUS laptop support enabled (battery charge limit set to 80%).${RESET}"
  else
    echo -e "${BOLD}Writing hardware-local.nix to enable OpenRGB for ASUS desktop...${RESET}"
    sudo tee /mnt/etc/nixos/hardware-local.nix > /dev/null << 'ASUSNIX'
# /etc/nixos/hardware-local.nix
# Written by bare-metal-install.sh — ASUS desktop (Aura RGB via OpenRGB).
{ pkgs, ... }: {
  environment.systemPackages = [ pkgs.openrgb-with-all-plugins ];
  boot.kernelModules = [ "i2c-dev" ];
  services.udev.packages = [ pkgs.openrgb-with-all-plugins ];
}
ASUSNIX
    echo -e "  ${GREEN}✓ OpenRGB enabled for ASUS desktop Aura RGB control.${RESET}"
  fi
fi

# ---------- Write the user-password override --------------------------------
# Required for every role — see the "Prompt: nimda user password" comment
# above for why. Two different filenames: the stateless role already has its
# own, tested mechanism (stateless-user-override.nix, also written by
# migrate-to-stateless.sh); every other role uses the new, generic
# user-override.nix instead, so stateless's mechanism is untouched.
echo ""
if $STATELESS; then
  echo -e "${BOLD}Writing stateless-user-override.nix with password hash...${RESET}"
  sudo tee /mnt/etc/nixos/stateless-user-override.nix > /dev/null << NIXEOF
{ lib, ... }: {
  users.users.nimda.hashedPassword = lib.mkOverride 50 "${HASHED_PW}";
}
NIXEOF
  # tee writes with the invoking process's umask (0644 on the live ISO) —
  # tighten to root-only since this file carries a crackable password hash.
  sudo chmod 0600 /mnt/etc/nixos/stateless-user-override.nix
  echo -e "  ${GREEN}✓ /mnt/etc/nixos/stateless-user-override.nix written.${RESET}"
else
  echo -e "${BOLD}Writing user-override.nix with password hash...${RESET}"
  sudo tee /mnt/etc/nixos/user-override.nix > /dev/null << NIXEOF
# /etc/nixos/user-override.nix
# Written by bare-metal-install.sh — initial login password for nimda.
{ lib, ... }: {
  users.users.nimda.hashedPassword = lib.mkOverride 50 "${HASHED_PW}";
}
NIXEOF
  sudo chmod 0600 /mnt/etc/nixos/user-override.nix
  echo -e "  ${GREEN}✓ /mnt/etc/nixos/user-override.nix written.${RESET}"
fi

# ---------- Write vm-platform.nix (VirtualBox guests only) ------------------
# "qemu" is the vexos.vm.platform default, so a QEMU/Proxmox guest needs no
# file. Must be written before `git add .` below so git+file:// picks it up.
# Shared by all six roles (template/etc-nixos-flake.nix's localFiles) — one
# mechanism for every role, not a per-role special case.
if [ "$VM_PLATFORM" = "virtualbox" ]; then
  echo ""
  echo -e "${BOLD}Writing vm-platform.nix (vexos.vm.platform = virtualbox)...${RESET}"
  sudo tee /mnt/etc/nixos/vm-platform.nix > /dev/null << 'VMPLATFORMEOF'
# /etc/nixos/vm-platform.nix
# Hypervisor selector for this VM guest. Written by bare-metal-install.sh
# when VirtualBox is chosen.
{
  vexos.vm.platform = "virtualbox";
}
VMPLATFORMEOF
  echo -e "${GREEN}  ✓ /mnt/etc/nixos/vm-platform.nix written.${RESET}"
fi

# ---------- Git-track the flake so Nix uses git+file: not path:+narHash ------
# Without git tracking, `nixos-install` locks /mnt/etc/nixos as a path: flake
# with a narHash.  Writing the lock file then changes the directory content,
# which causes a Nix assertion failure (narHash mismatch).  Initialising a git
# repo and staging all files makes Nix use git+file: instead, which is stable.
# The .git directory is also persisted (stateless only — see below) so that
# post-boot `vexos-update` can use git+file:///etc/nixos URIs — keeping
# secrets/ out of the world-readable Nix store.
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
# Lock vexos-nix to this run's commit (VEXOS_REV) before installing.
# Without this, nixos-install creates a fresh flake.lock using whatever commit
# GitHub's CDN happens to serve for the main branch — which may be a stale
# cached revision if the branch was recently updated.  A stale commit can carry
# bugs that have already been fixed in the current HEAD (e.g. the broken
# lib.mkForce placement in modules/stateless-disk.nix that existed at c238ce6).
# Pinning to VEXOS_REV also keeps the installed config identical to the scripts
# that ran; the pin lives only in flake.lock, so a later `just update` moves to
# main as usual.
echo ""
echo -e "${CYAN}Refreshing flake inputs...${RESET}"
sudo nix --extra-experimental-features "nix-command flakes" \
  flake update --flake git+file:///mnt/etc/nixos \
  --override-input vexos-nix "github:VictoryTek/vexos-nix/${VEXOS_REV}"

# ---------- Run nixos-install ------------------------------------------------
FLAKE_TARGET="vexos-${ROLE}-${VARIANT}${NVIDIA_SUFFIX}"
echo ""
echo -e "${BOLD}Running nixos-install targeting ${CYAN}${FLAKE_TARGET}${RESET}${BOLD}...${RESET}"
echo -e "${YELLOW}This may take a while — it will download and build the NixOS closure.${RESET}"
echo ""
render_header
if run_live_build "Building ${FLAKE_TARGET}..." \
     sudo nixos-install --no-root-passwd --flake "/mnt/etc/nixos#${FLAKE_TARGET}"; then
  echo -e "${GREEN}  ✓ nixos-install complete.${RESET}"
else
  echo ""
  echo -e "${RED}${BOLD}✗ nixos-install failed.${RESET}"
  echo "  Last 60 lines of the install log (${BUILD_LOG_PATH}):"
  echo ""
  tail -n 60 "${BUILD_LOG_PATH}" 2>/dev/null || true
  echo ""
  echo -e "${RED}Installation incomplete — review the log above and re-run.${RESET}"
  exit 1
fi

if $STATELESS; then
  # ---------- Persist nixos config to /persistent ---------------------------
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
  sudo cp -p /mnt/etc/nixos/stateless-user-override.nix /mnt/persistent/etc/nixos/ 2>/dev/null || true
  sudo cp /mnt/etc/nixos/vm-platform.nix /mnt/persistent/etc/nixos/ 2>/dev/null || true
  sudo cp /mnt/etc/nixos/hardware-local.nix /mnt/persistent/etc/nixos/ 2>/dev/null || true
  printf '%s' "vexos-stateless-${VARIANT}${NVIDIA_SUFFIX}" | sudo tee /mnt/persistent/etc/nixos/vexos-variant > /dev/null
  # Persist the git repo so post-boot git+file:///etc/nixos URIs work and secrets stay out of the Nix store.
  sudo cp -r /mnt/etc/nixos/.git /mnt/persistent/etc/nixos/
  echo -e "${GREEN}✓ NixOS config files persisted.${RESET}"
fi
# Conventional roles: /mnt IS the real, persistent root filesystem (not
# ephemeral tmpfs), so /mnt/etc/nixos already survives the reboot as-is —
# nothing to copy anywhere.

echo ""
echo -e "${GREEN}${BOLD}============================================================${RESET}"
echo -e "${GREEN}${BOLD}  ✓ VexOS ${ROLE} installation complete!${RESET}"
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
if $STATELESS; then
  echo -e "${YELLOW}Note: Passwords changed at runtime do NOT persist across reboots.${RESET}"
  echo -e "${YELLOW}      The password resets to the configured value on every boot (by design).${RESET}"
  echo ""
fi
if preset_yes_no REBOOT no; then  # --reboot; default no when unattended
  REBOOT_CHOICE="$PRESET_YN"
else
  printf "Reboot now? [y/N] "
  read -r REBOOT_CHOICE </dev/tty
fi
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
