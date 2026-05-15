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

  assertions = [
    {
      assertion = config.networking.hostId != "00000000";
      message = ''
        ZFS requires a unique networking.hostId per machine.
        Set it in hosts/<role>-<gpu>.nix or hardware-configuration.nix:
          networking.hostId = "deadbeef";   # replace with real value
        Generate with: head -c 8 /etc/machine-id
      '';
    }
  ];
}
