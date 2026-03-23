# modules/performance.nix
# Gaming-grade kernel and performance tuning: zen kernel, kernel params,
# ZRAM swap, CPU governor, BBR TCP, VM tunables, transparent huge pages.
{ config, pkgs, lib, ... }:
{
  # ── Kernel selection ──────────────────────────────────────────────────────
  # zen: preemptive, tickless, optimized for desktop/gaming latency.
  # Alternatives:
  #   pkgs.linuxPackages_lqx    — Liquorix: includes BORE scheduler, more aggressive tuning
  #   pkgs.linuxPackages_xanmod — XanMod: BORE + BBR3 + x86-64-v3 optimizations
  #   pkgs.linuxPackages_latest — Latest mainline (bleeding edge)
  boot.kernelPackages = pkgs.linuxPackages_zen;

  # ── Kernel parameters ─────────────────────────────────────────────────────
  boot.kernelParams = [
    # Full preemption — lowest desktop/gaming latency
    "preempt=full"

    # Disable split-lock detection for better Wine/Proton compatibility
    "split_lock_detect=off"

    # I/O scheduler: Kyber is low-latency; well suited for NVMe SSDs.
    # Override per-device via udev if mixing SSDs and HDDs.
    "elevator=kyber"

    # Clean boot experience (matches Bazzite)
    "quiet"
    "splash"
    "loglevel=3"

    # CPU vulnerability mitigations — kept enabled (safe default).
    # Uncomment below ONLY if performance is critical and security trade-off is accepted:
    # "mitigations=off"
  ];

  # ── Plymouth (graphical boot splash) ─────────────────────────────────────
  boot.plymouth.enable = true;

  # ── ZRAM swap ─────────────────────────────────────────────────────────────
  # Matches Bazzite: compressed in-RAM swap. lz4 gives the best speed/ratio balance.
  zramSwap = {
    enable = true;
    algorithm = "lz4";
    memoryPercent = 50; # up to 50% of physical RAM as compressed swap
  };

  # ── CPU frequency governor ────────────────────────────────────────────────
  # schedutil (zen default): good gaming perf with power efficiency.
  # Change to "performance" for absolute lowest latency at the cost of power draw.
  powerManagement.cpuFreqGovernor = lib.mkDefault "schedutil";

  # ── Kernel sysctl tunables ────────────────────────────────────────────────
  boot.kernel.sysctl = {
    # BBR TCP congestion control (matches Bazzite / SteamOS)
    "net.core.default_qdisc"          = "fq";
    "net.ipv4.tcp_congestion_control" = "bbr";

    # Reduce swap aggressiveness (good for gaming workloads)
    "vm.swappiness"            = 10;
    "vm.dirty_ratio"           = 20;
    "vm.dirty_background_ratio" = 5;

    # Increase file watch limits (needed for some game engines, IDEs, Electron apps)
    "fs.inotify.max_user_watches"   = 524288;
    "fs.inotify.max_user_instances" = 8192;

    # Increase socket buffer sizes for game streaming
    "net.core.rmem_max" = 16777216;
    "net.core.wmem_max" = 16777216;

    # SysRq — useful for emergency system recovery during gaming lockups
    "kernel.sysrq" = 1;
  };

  # ── Transparent Huge Pages ────────────────────────────────────────────────
  # madvise: allocate THP only when applications explicitly request it.
  # Applied at boot via systemd-tmpfiles.
  systemd.tmpfiles.rules = [
    "w /sys/kernel/mm/transparent_hugepage/enabled - - - - madvise"
    "w /sys/kernel/mm/transparent_hugepage/defrag   - - - - defer+madvise"
  ];

  # ── scx CPU scheduler (LAVD / BORE via scx_sched) ─────────────────────────
  # scx_lavd is the SteamOS/Bazzite scheduler for handhelds and gaming desktops.
  # Requires sched_ext support (zen 6.12+, lqx 6.12+).
  # services.scx may not be available in nixpkgs 24.11 (added in unstable).
  # Uncomment after confirming kernel and package availability:
  #
  # services.scx = {
  #   enable    = true;
  #   scheduler = "scx_lavd"; # or "scx_rusty", "scx_bpfland"
  # };
}
