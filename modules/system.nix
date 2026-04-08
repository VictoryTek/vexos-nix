# modules/system.nix
# Base system configuration: kernel, boot, performance tuning, swap, and
# btrfs snapshot management. Applies to all hosts; the btrfs section is
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
        Enable btrfs snapshot management (snapper), auto-scrub, and the
        btrfs-assistant GUI.  Defaults to true when the root filesystem
        reported in fileSystems is btrfs; false otherwise.  Can be
        overridden explicitly for edge cases.
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

      # ── Plymouth (graphical boot splash) ────────────────────────────────
      boot.plymouth.enable = true;

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

      # ── Transparent Huge Pages ───────────────────────────────────────────
      # madvise: allocate THP only when applications explicitly request it.
      systemd.tmpfiles.rules = [
        "w /sys/kernel/mm/transparent_hugepage/enabled - - - - madvise"
        "w /sys/kernel/mm/transparent_hugepage/defrag   - - - - defer+madvise"
      ];

      # ── scx CPU scheduler (LAVD / BORE via scx_sched) ───────────────────
      # scx_lavd is the SteamOS/Bazzite scheduler for gaming desktops.
      # Requires sched_ext support (zen 6.12+, lqx 6.12+).
      # Uncomment after confirming kernel and package availability:
      #
      # services.scx = {
      #   enable    = true;
      #   scheduler = "scx_lavd"; # or "scx_rusty", "scx_bpfland"
      # };
    }

    # ── Swap file (opt-out via vexos.swap.enable = false) ─────────────────
    # Persistent 8 GiB disk-backed swap at /var/lib/swapfile. Complements ZRAM:
    # ZRAM handles in-RAM compressed overflow first; swap file is last-resort
    # disk overflow for low-RAM configs and enables hibernate support.
    #
    # BTRFS + snapper: if using snapper on /, create a dedicated /swap btrfs
    # subvolume in hardware-configuration.nix to avoid snapshot conflicts.
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

    # ── btrfs: snapshots + scrub (opt-out via vexos.btrfs.enable = false) ─
    (lib.mkIf config.vexos.btrfs.enable {
      services.snapper.configs = {
        root = {
          SUBVOLUME = "/";
          ALLOW_USERS = [ "nimda" ];
          TIMELINE_CREATE = true;
          TIMELINE_CLEANUP = true;
          TIMELINE_MIN_AGE = 1800;
          TIMELINE_LIMIT_HOURLY = 5;
          TIMELINE_LIMIT_DAILY = 7;
          TIMELINE_LIMIT_WEEKLY = 4;
          TIMELINE_LIMIT_MONTHLY = 3;
          TIMELINE_LIMIT_YEARLY = 0;
          NUMBER_LIMIT = "50";
          NUMBER_LIMIT_IMPORTANT = "10";
        };
      };

      services.snapper.snapshotRootOnBoot = true;
      services.snapper.persistentTimer = true;

      # Create /.snapshots subvolume on first activation.
      # Idempotent — snapper requires this subvolume before its services start.
      system.activationScripts.snapperSubvolume = {
        text = ''
          if ! ${pkgs.btrfs-progs}/bin/btrfs subvolume show /.snapshots >/dev/null 2>&1; then
            ${pkgs.btrfs-progs}/bin/btrfs subvolume create /.snapshots
          fi
        '';
        deps = [];
      };

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
