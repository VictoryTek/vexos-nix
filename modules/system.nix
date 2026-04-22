# modules/system.nix
# Base system configuration: kernel, boot, performance tuning, swap, and
# btrfs maintenance. Applies to all hosts; the btrfs section is
# auto-enabled when the root filesystem is btrfs (detected from fileSystems)
# and can still be forced on/off via vexos.btrfs.enable.
{ pkgs, lib, config, ... }:
{
  options = {
    vexos.btrfs.enable = lib.mkOption {
      type    = lib.types.bool;
      # Auto-detect: enable only when / is actually a btrfs subvolume.
      # Override explicitly if hardware-configuration.nix is not yet present
      # or if you want to force the behaviour in either direction.
      default = (config.fileSystems ? "/") && (config.fileSystems."/".fsType == "btrfs");
      description = ''
        Enable btrfs auto-scrub and the btrfs-assistant GUI.
        Defaults to true when the root filesystem reported in fileSystems
        is btrfs; false otherwise.  Can be overridden explicitly for edge cases.
      '';
    };

    vexos.system.gaming = lib.mkOption {
      type        = lib.types.bool;
      default     = false;
      description = ''
        Enable gaming-optimised kernel parameters, CPU scheduler (SCX LAVD),
        and Proton/Wine compatibility tunables. Set to true on desktop and gaming roles.
      '';
    };

    vexos.scx.enable = lib.mkOption {
      type    = lib.types.bool;
      default = true;
      description = ''
        Enable the scx CPU scheduler (scx_lavd) for gaming desktops.
        Requires kernel >= 6.12 with sched_ext support. Set to false on
        VM guests or any host running a kernel older than 6.12.
      '';
    };

    vexos.swap.enable = lib.mkOption {
      type    = lib.types.bool;
      default = true;
      description = ''
        Enable an 8 GiB persistent swap file at /var/lib/swapfile.
        Provides true overflow capacity beyond RAM + ZRAM, and enables
        system hibernate support. Set to false on VM guests.
      '';
    };
  };

  config = lib.mkMerge [

    # ── Unconditional: kernel, boot, performance ──────────────────────────
    {
      # Latest upstream kernel — applies to all variants.
      boot.kernelPackages = pkgs.linuxPackages_latest;

      # ── Kernel parameters ───────────────────────────────────────────────
      boot.kernelParams = [
        # I/O scheduler: Kyber is low-latency; well suited for NVMe SSDs.
        # Override per-device via udev if mixing SSDs and HDDs.
        "elevator=kyber"
      ];

      # ── Plymouth (graphical boot splash) ────────────────────────────────
      # Display roles set boot.plymouth.enable = true in their config.
      boot.plymouth.enable = lib.mkDefault false;

      # ── ZRAM swap ────────────────────────────────────────────────────────
      # Compressed in-RAM swap (matches Bazzite). lz4 gives best speed/ratio.
      zramSwap = {
        enable = true;
        algorithm = "lz4";
        memoryPercent = 50; # up to 50% of physical RAM as compressed swap
      };

      # ── CPU frequency governor ───────────────────────────────────────────
      # schedutil: good gaming perf with power efficiency.
      # Change to "performance" for absolute lowest latency at cost of power.
      powerManagement.cpuFreqGovernor = lib.mkDefault "schedutil";

      # ── Kernel sysctl tunables ───────────────────────────────────────────
      boot.kernel.sysctl = {
        # BBR TCP congestion control (matches Bazzite / SteamOS)
        "net.core.default_qdisc"          = "fq";
        "net.ipv4.tcp_congestion_control" = "bbr";

        # Reduce swap aggressiveness (good for gaming workloads)
        "vm.swappiness"             = 10;
        "vm.dirty_ratio"            = 20;
        "vm.dirty_background_ratio" = 5;

        # Increase file watch limits (needed for game engines, IDEs, Electron)
        "fs.inotify.max_user_watches"   = 524288;
        "fs.inotify.max_user_instances" = 8192;

        # Increase socket buffer sizes for game streaming
        "net.core.rmem_max" = 16777216;
        "net.core.wmem_max" = 16777216;

        # SysRq — useful for emergency system recovery during gaming lockups
        "kernel.sysrq" = 1;
      };

    }

    # ── Gaming-specific tuning (opt-in via vexos.system.gaming = true) ────
    (lib.mkIf config.vexos.system.gaming {
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

      # ── Transparent Huge Pages ─────────────────────────────────────────
      # madvise: allocate THP only when applications explicitly request it.
      systemd.tmpfiles.rules = [
        "w /sys/kernel/mm/transparent_hugepage/enabled - - - - madvise"
        "w /sys/kernel/mm/transparent_hugepage/defrag   - - - - defer+madvise"
      ];
    })

    # ── scx CPU scheduler — active only when gaming + scx enabled ─────────
    # scx_lavd is the SteamOS/Bazzite scheduler for gaming desktops.
    # Requires sched_ext support (zen 6.12+, lqx 6.12+, upstream 6.14+).
    # Disabled automatically on VM guests (kernel 6.6 LTS, below minimum).
    #
    (lib.mkIf (config.vexos.system.gaming && config.vexos.scx.enable) {
      services.scx = {
        enable    = true;
        scheduler = "scx_lavd";
      };
    })

    # ── Swap file (opt-out via vexos.swap.enable = false) ─────────────────
    # Persistent 8 GiB disk-backed swap at /var/lib/swapfile. Complements ZRAM:
    # ZRAM handles in-RAM compressed overflow first; swap file is last-resort
    # disk overflow for low-RAM configs and enables hibernate support.
    #
    (lib.mkIf config.vexos.swap.enable {
      swapDevices = [
        {
          device = "/var/lib/swapfile";
          size   = 8192; # 8 GiB in MiB — NixOS creates the file automatically
          # randomEncryption intentionally omitted:
          #   - Breaks hibernate (saved image unreadable on resume)
          #   - No benefit on LUKS-encrypted drives
        }
      ];
    })

    # ── btrfs: scrub (opt-out via vexos.btrfs.enable = false) ─────────────
    (lib.mkIf config.vexos.btrfs.enable {
      services.btrfs.autoScrub = {
        enable = true;
        interval = "monthly";
        fileSystems = [ "/" ];
      };

      environment.systemPackages = with pkgs; [
        btrfs-assistant
        btrfs-progs
      ];
    })

  ];
}
