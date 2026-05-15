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

    vexos.swap.enable = lib.mkOption {
      type    = lib.types.bool;
      default = true;
      description = ''
        Enable an 8 GiB persistent swap file at /var/lib/swapfile.
        Provides true overflow capacity beyond RAM + ZRAM, and enables
        system hibernate support.
        Defaults to false on ZFS server roles (modules/zfs-server.nix) to
        avoid the ZFS+swap kernel deadlock; false on VM guests (modules/gpu/vm.nix)
        and stateless hosts (modules/impermanence.nix). All other roles default
        to true.
      '';
    };
  };

  config = lib.mkMerge [

    # ── Unconditional: kernel, boot, performance ──────────────────────────
    {
      # Latest upstream kernel — applies to all variants.
      boot.kernelPackages = pkgs.linuxPackages_latest;

      # EFI / systemd-boot — standard bootloader for all vexos-nix hosts.
      # lib.mkDefault allows the host's /etc/nixos/flake.nix thin wrapper
      # to override for BIOS/GRUB systems without conflict.
      boot.loader.systemd-boot.enable           = lib.mkDefault true;
      boot.loader.systemd-boot.configurationLimit = 5;  # keep only the 5 latest boot entries
      boot.loader.efi.canTouchEfiVariables      = lib.mkDefault true;

      # EDK2 UEFI Shell — enables booting other OSes on separate drives and
      # provides a diagnostic shell for EFI troubleshooting. Required for
      # boot.loader.systemd-boot.windows entries to function.
      boot.loader.systemd-boot.edk2-uefi-shell.enable = true;

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
