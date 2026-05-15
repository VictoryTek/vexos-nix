# modules/system-gaming.nix
# Gaming-optimised kernel parameters, vm.max_map_count, Transparent Huge Pages,
# and the SCX LAVD CPU scheduler.
#
# Import in any configuration that requires gaming-level kernel tuning.
# Do NOT import on VM guests or headless roles.
#
# If a specific host must disable SCX (e.g. a VM pinned to a kernel < 6.12
# that lacks sched_ext support), override in the host file:
#   services.scx.enable = lib.mkForce false;
{ ... }:
{
  boot.kernelParams = [
    # Full preemption — lowest desktop/gaming latency
    "preempt=full"

    # Disable split-lock detection for better Wine/Proton compatibility
    "split_lock_detect=off"

    # Clean boot experience (matches Bazzite)
    "quiet"
    "splash"
    "loglevel=3"
  ];

  # Maximum memory map areas per process — required by Proton/Wine anti-cheat
  # (EAC, BattlEye). 2147483642 is MAX_INT-5, the value set by SteamOS/Bazzite.
  boot.kernel.sysctl."vm.max_map_count" = 2147483642;

  # ── Transparent Huge Pages ────────────────────────────────────────────────
  # madvise: allocate THP only when applications explicitly request it.
  systemd.tmpfiles.rules = [
    "w /sys/kernel/mm/transparent_hugepage/enabled - - - - madvise"
    "w /sys/kernel/mm/transparent_hugepage/defrag   - - - - defer+madvise"
  ];

  # ── SCX LAVD CPU scheduler ────────────────────────────────────────────────
  # SteamOS/Bazzite scheduler — optimised for gaming desktops.
  # Requires sched_ext support (upstream 6.14+, zen 6.12+, lqx 6.12+).
  # Override with lib.mkForce false in the host file if running a kernel
  # older than 6.12 that lacks sched_ext (e.g. the VM 6.6 LTS pin).
  services.scx = {
    enable    = true;
    scheduler = "scx_lavd";
  };

  # Enable oomd monitoring on user and root slices
  systemd.oomd = {
    enableRootSlice  = true;
    enableUserSlices = true;
  };
}
