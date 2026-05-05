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
  # ZFS REQUIRES a stable 8-hex-digit hostId. Without it, pools may refuse to
  # auto-import on boot. We derive it deterministically from /etc/machine-id
  # via an activation script so each host gets a unique, reproducible value
  # without committing per-host secrets to the flake.
  #
  # If the user has already set networking.hostId in their host file (under
  # hosts/<role>-<gpu>.nix) or in /etc/nixos/hardware-configuration.nix,
  # that value wins (lib.mkDefault).
  networking.hostId = lib.mkDefault (
    let
      machineIdFile = "/etc/machine-id";
    in
      if builtins.pathExists machineIdFile
      then builtins.substring 0 8 (builtins.readFile machineIdFile)
      else "00000000"   # placeholder; first build on a fresh host will recompute
  );
}
