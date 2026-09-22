# shellcheck shell=bash
# =============================================================================
# scripts/lib/swap.sh — shared temporary install-time swap
# (install.sh, bare-metal-install.sh, migrate-to-stateless.sh).
#
# Extracted so the three scripts agree on when a swapfile is worth creating:
# install.sh guarded on RAM/free-space/filesystem; both stateless scripts
# created one unconditionally. Those guards are now shared by all three —
# only the swapfile's path, size, and post-install lifecycle differ per
# caller (see each call site's own comment for why).
#
# Sourced by lib/bootstrap.sh, never executed.
# =============================================================================

# ensure_install_swap <swapfile-path> <size-mib>
#
# One evaluation of a desktop configuration peaks around 1.7 GiB, and packages
# that are in no binary cache at all (NVIDIA's proprietary driver, noctalia,
# up/vexportal's Rust release builds) add to that. A machine with well under
# 8 GiB of RAM+swap can get its build killed by the OOM killer. This creates a
# temporary swapfile to cover that window.
#
# Best-effort and guarded — never fails the caller under `set -e`:
#   - RAM+swap already >= 8 GiB: skip, there's already enough headroom.
#   - the filesystem containing <swapfile-path> is tmpfs or zfs: skip, neither
#     can host a swapfile the way this function creates one.
#   - free space on that filesystem is under <size-mib> + 6 GiB headroom
#     (same ratio as this function's original 4 GiB swap / 10 GiB free check):
#     skip rather than risk filling the disk.
# Btrfs targets use `btrfs filesystem mkswapfile` (handles NOCOW/nodatasum
# itself); anything else uses dd + mkswap (fallocate leaves unwritten extents
# that swapon rejects on ext4).
#
# Sets INSTALL_SWAP_ACTIVE=true|false. Activation only — the caller owns
# swapoff, and rm if the file should not outlive this script; some callers
# deliberately leave it in place (see their own comments), so that lifecycle
# is not something this function can decide on their behalf.
ensure_install_swap() {
  local swap_path="$1" size_mib="$2"
  local swap_dir mem_kb swap_kb total_gib target_fs free_mib required_mib

  # shellcheck disable=SC2034  # INSTALL_SWAP_ACTIVE is this function's output contract
  INSTALL_SWAP_ACTIVE=false
  swap_dir="$(dirname "$swap_path")"

  mem_kb=$(awk '/^MemTotal:/{print $2}' /proc/meminfo)
  swap_kb=$(awk '/^SwapTotal:/{print $2}' /proc/meminfo)
  total_gib=$(( (mem_kb + swap_kb) / 1048576 ))
  echo ""
  echo -e "${CYAN}Memory available to the build: $(( mem_kb / 1048576 )) GiB RAM + $(( swap_kb / 1048576 )) GiB swap.${RESET}"

  if [ "$total_gib" -ge 8 ]; then
    return 0
  fi

  # -T resolves swap_dir to whatever filesystem contains it, rather than
  # requiring swap_dir itself to be an exact mountpoint — migrate-to-stateless.sh's
  # target is a Btrfs subvolume directory, not a separate mount.
  target_fs=$(findmnt -n -o FSTYPE -T "$swap_dir" 2>/dev/null || echo unknown)
  if [ "$target_fs" = "tmpfs" ] || [ "$target_fs" = "zfs" ]; then
    echo -e "${YELLOW}⚠ ${swap_dir} is on ${target_fs} — cannot add a temporary swapfile there."
    echo -e "  With under 8 GiB total the build may be killed by the OOM killer;"
    echo -e "  raise the machine's RAM if it fails.${RESET}"
    return 0
  fi

  free_mib=$(df -P -BM "$swap_dir" | awk 'NR==2{sub(/M$/,"",$4); print $4}')
  required_mib=$(( size_mib + 6144 ))
  if [ "${free_mib:-0}" -lt "$required_mib" ]; then
    echo -e "${YELLOW}⚠ Less than $(( required_mib / 1024 )) GiB free on ${swap_dir} — skipping the temporary swapfile.${RESET}"
    return 0
  fi

  echo -e "${CYAN}Under 8 GiB total — adding a temporary $(( size_mib / 1024 )) GiB swapfile for the build...${RESET}"
  sudo rm -f "$swap_path"
  # Whole creation runs in a subshell so a failure is best-effort (consumed by
  # `if`) instead of aborting the installer under `set -e`.
  if ( set -e
       if [ "$target_fs" = "btrfs" ]; then
         # A plain file cannot be swapped on btrfs (needs nocow + nodatasum);
         # `mkswapfile` creates it with the required attributes. --uuid clear
         # avoids a stale/duplicate swap signature confusing a freshly
         # (re)created disk.
         sudo btrfs filesystem mkswapfile --size "${size_mib}M" --uuid clear "$swap_path"
       else
         # dd rather than fallocate: swapon rejects the unwritten extents
         # fallocate leaves behind on ext4.
         sudo dd if=/dev/zero of="$swap_path" bs=1M count="$size_mib" status=none
         sudo chmod 600 "$swap_path"
         sudo mkswap -q "$swap_path"
       fi
       sudo swapon "$swap_path" ); then
    # shellcheck disable=SC2034  # INSTALL_SWAP_ACTIVE is this function's output contract
    INSTALL_SWAP_ACTIVE=true
    echo -e "${GREEN}✓ Temporary $(( size_mib / 1024 )) GiB swapfile active.${RESET}"
  else
    sudo rm -f "$swap_path"
    echo -e "${YELLOW}⚠ Could not activate a temporary swapfile — continuing without it.${RESET}"
  fi
}
