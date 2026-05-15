# modules/zfs-server.nix
# ZFS support for server roles — required for proxmox-nixos VM storage.
#
# Why this is a server-only addition:
#   • Loads the ZFS kernel module on every boot (overhead on roles that don't
#     need it, plus ZFS+nvidia-headless DKMS interactions can lengthen rebuilds).
#   • networking.hostId must be globally unique per machine; setting it on
#     desktop/htpc/stateless variants without ZFS adds noise.
#
# Per the Option B module pattern (see .github/copilot-instructions.md):
#   imported ONLY by configuration-server.nix and configuration-headless-server.nix.
{ config, lib, pkgs, ... }:
{
  # ── Kernel + userland ────────────────────────────────────────────────────
  boot.supportedFilesystems        = [ "zfs" ];
  boot.zfs.forceImportRoot         = false;   # backing pools are not the rootfs
  boot.zfs.forceImportAll          = false;

  # ── Kernel pinning for ZFS compatibility ─────────────────────────────────
  # ZFS releases regularly lag behind linuxPackages_latest, and when nixpkgs'
  # `pkgs.linuxPackages_latest` advances past ZFS's "latest supported kernel"
  # the zfs-kernel derivation is marked broken and evaluation fails with:
  #
  #   error: Package 'zfs-kernel-X.Y.Z-A.B.C' is marked as broken,
  #          refusing to evaluate.
  #
  # (Observed in CI for vexos-headless-server-{amd,nvidia,intel}; the vm
  #  variant escaped because modules/gpu/vm.nix already pins the kernel to
  #  linuxPackages_6_6 for VirtualBox guest-additions compatibility.)
  #
  # Pin server roles to the LTS kernel to maintain ZFS compatibility.
  # Priority 75 beats the plain assignment in modules/system.nix
  # (priority 100, `pkgs.linuxPackages_latest`) but intentionally loses to
  # `lib.mkForce` (priority 50) in modules/gpu/vm.nix, so the headless-server
  # VM variant keeps its own LTS pin without raising a duplicate-priority conflict.
  #
  # Note: zfs.package.latestCompatibleLinuxPackages was deprecated in NixOS 25.05
  # and now just aliases the default kernel without any ZFS-specific pinning logic.
  # Using pkgs.linuxPackages (the default LTS, currently 6.12) directly is the correct replacement.
  boot.kernelPackages = lib.mkOverride 75 pkgs.linuxPackages;


  boot.zfs.extraPools              = [ ];     # auto-imported pools added by `just create-zfs-pool` are cached in /etc/zfs/zpool.cache, not listed here
  services.zfs.autoScrub.enable    = true;
  services.zfs.autoScrub.interval  = "monthly";
  services.zfs.trim.enable         = true;
  services.zfs.trim.interval       = "weekly";

  # ── Userland tools needed by scripts/create-zfs-pool.sh ──────────────────
  environment.systemPackages = with pkgs; [
    zfs           # zpool, zfs (also pulled in by boot.supportedFilesystems but listed for clarity)
    gptfdisk      # sgdisk
    util-linux    # wipefs, lsblk
    pciutils      # lspci (optional, for disk topology hints)
  ];

  # ── networking.hostId ────────────────────────────────────────────────────
  # ZFS REQUIRES a stable, unique 8-hex-digit hostId per machine.
  # Do NOT read /etc/machine-id at eval time — that file belongs to the machine
  # running `nixos-rebuild`, not the target host.  When building a server
  # closure on a workstation every server would inherit the workstation's
  # hostId, causing ZFS to refuse pool import on next boot.
  #
  # Set networking.hostId explicitly in hosts/<role>-<gpu>.nix, e.g.:
  #   networking.hostId = "deadbeef";
  # Generate a value with:  head -c 8 /etc/machine-id
  networking.hostId = lib.mkDefault "00000000";

  # ── Swap policy: disable disk-backed swap on ZFS hosts ───────────────────
  # Writing a swapfile to a ZFS dataset risks a kernel deadlock: the kernel's
  # memory-reclaim path writes to swap (on ZFS), ZFS needs to shrink its ARC
  # to service the write, but ARC shrink itself blocks on memory reclaim.
  # See: https://openzfs.github.io/openzfs-docs/Performance%20and%20Tuning/Memory%20Management.html
  #
  # lib.mkDefault (priority 1000) is weaker than a plain assignment (priority 100),
  # so a host operator can override this by setting:
  #   vexos.swap.enable = true;   # in hosts/<role>-<gpu>.nix
  # only if they have a confirmed non-ZFS swap partition or file.
  #
  # ZRAM swap (configured unconditionally in modules/system.nix) is unaffected
  # and continues to provide fast in-RAM compressed swap on all server roles.
  vexos.swap.enable = lib.mkDefault false;

  # Warn (not assert) so fresh installs that haven't yet created any ZFS pools
  # can still complete their first build.  Once you run `just create-zfs-pool`,
  # the pool vdev label is stamped with the current hostId — at that point you
  # MUST have a real value here or ZFS will refuse to import the pool on reboot.
  warnings = lib.optionals (config.networking.hostId == "00000000") [
    ''
      ZFS: networking.hostId is still set to the placeholder "00000000".
      This is fine for a fresh install, but you MUST set a real value before
      creating any ZFS pools (just create-zfs-pool / zpool create).
      Add to /etc/nixos/hardware-configuration.nix (or a local override):
        networking.hostId = "deadbeef";   # replace with real value
      Generate: head -c 8 /etc/machine-id
    ''
  ];
}
