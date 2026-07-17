# modules/server/nas.nix
# Umbrella option for the full NAS stack.
#
# Setting `vexos.server.nas.enable = true` is the "just make it a NAS"
# shortcut. It enables Cockpit plus all four 45Drives management plugins:
#   • cockpit-navigator   — file browser
#   • cockpit-file-sharing — Samba + NFS share management
#   • cockpit-identities  — user/group/password management
#
# Each sub-option is set via lib.mkDefault, so the operator can still
# override individual sub-options without having to touch nas.enable:
#
#   vexos.server.nas.enable = true;
#   vexos.server.cockpit.navigator.enable = false;  # this wins — lib.mkDefault loses
#
# cockpit-zfs is intentionally excluded: it requires a ZFS pool to already
# be configured on the host and has its own default auto-enable logic.
# Re-checked at this repo's pinned nixpkgs rev (2026-07): pkgs.cockpit-zfs
# now exists but still fails to build — see modules/server/cockpit.nix for
# the current blocking reason. When it builds, adding it here is a one-line
# addition to this file.
{ config, lib, ... }:
let
  cfg = config.vexos.server.nas;
in
{
  options.vexos.server.nas = {
    enable = lib.mkEnableOption "full NAS stack (Cockpit web UI + navigator + file-sharing + identities plugins)";

    backend = lib.mkOption {
      type = lib.types.enum [ "zfs" "mergerfs" ];
      default = "zfs";
      description = ''
        Which LOCAL storage pool recipe this host uses for NAS/bulk storage:
          • "zfs"      — the existing ZFS pool (modules/zfs-server.nix +
                         `just create-zfs-pool`). Best for matched disks and
                         realtime redundancy; also the Proxmox VM tier.
          • "mergerfs" — a mergerfs union pool (+ optional SnapRAID parity) for
                         mixed-capacity, add-one-at-a-time bulk/media storage.
                         Enables vexos.server.storage.mergerfs; the actual disk
                         list and SnapRAID config are written to
                         /etc/nixos/storage-pool.nix by `just create-mergerfs-pool`.
        This is orthogonal to vexos.server.storage.remote (attaching a pool
        from another host), which can be used with either backend or on its own.
      '';
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      vexos.server.cockpit.enable             = lib.mkDefault true;
      vexos.server.cockpit.navigator.enable   = lib.mkDefault true;
      vexos.server.cockpit.fileSharing.enable = lib.mkDefault true;
      vexos.server.cockpit.identities.enable  = lib.mkDefault true;
    })

    # The mergerfs backend enables the union-pool module. SnapRAID is enabled
    # independently by the generated storage-pool.nix (only when parity disks
    # are allocated), so it is NOT force-enabled here — a mergerfs pool without
    # parity is a valid (unprotected) configuration.
    (lib.mkIf (cfg.backend == "mergerfs") {
      vexos.server.storage.mergerfs.enable = lib.mkDefault true;
    })
  ];
}
