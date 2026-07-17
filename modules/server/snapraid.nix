# modules/server/snapraid.nix
# SnapRAID parity — the redundancy layer for the mergerfs bulk tier.
#
# SnapRAID computes parity across the mergerfs content disks onto dedicated
# parity disk(s), refreshed on a schedule (out-of-band, not per-write). On a
# disk failure, `snapraid fix` rebuilds only that disk's used capacity from
# parity + surviving disks. This is the correct redundancy model for large,
# infrequently-changing files (media) — NOT for databases or churny data,
# which belong on the ZFS live tier instead.
#
# Trade-off vs. ZFS: protection is only as fresh as the last `sync`. Anything
# written since the last sync is unprotected until the next run. Accepted
# deliberately for the bulk tier; steer churny/DB services to ZFS.
#
# This is a thin wrapper over the upstream `services.snapraid` module (which
# writes /etc/snapraid.conf, adds the snapraid package, and defines the
# snapraid-sync / snapraid-scrub systemd services + timers). It exists to:
#   • auto-derive data disks from the mergerfs branches (no double-declaration),
#   • declare the parity disks' own mounts (NixOS generates /etc/fstab),
#   • wire failure notifications through vexos-notify (see modules/notify.nix).
#
# Per the Option B module pattern: options + config gated by this module's own
# `enable`. Inert until vexos.server.storage.snapraid.enable = true.
{ config, lib, ... }:
let
  cfg = config.vexos.server.storage.snapraid;
  mergerfsBranches = config.vexos.server.storage.mergerfs.branches;

  parityModule = lib.types.submodule {
    options = {
      mountPoint = lib.mkOption {
        type = lib.types.str;
        example = "/mnt/parity1";
        description = "Local mountpoint for this parity disk.";
      };
      device = lib.mkOption {
        type = lib.types.str;
        example = "/dev/disk/by-uuid/3333-4444";
        description = "Block device for the parity disk, by-uuid or by-id.";
      };
      fsType = lib.mkOption {
        type = lib.types.str;
        default = "ext4";
        description = "Filesystem on the parity disk (ext4 or xfs).";
      };
    };
  };

  # SnapRAID parity file naming convention: first is "snapraid.parity", the
  # rest are "snapraid.<n>-parity" (2-parity, 3-parity, ...).
  parityFileName = i: if i == 1 then "snapraid.parity" else "snapraid.${toString i}-parity";

  # fileSystems entries for the parity disks (mirrors mergerfs branch mounts).
  parityFileSystems = builtins.listToAttrs (map (p: {
    name = p.mountPoint;
    value = {
      device = p.device;
      fsType = p.fsType;
      options = [ "defaults" "nofail" ];
    };
  }) cfg.parityDisks);
in
{
  options.vexos.server.storage.snapraid = {
    enable = lib.mkEnableOption "SnapRAID parity protection for the mergerfs bulk pool";

    dataDisks = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      # Auto-derive from the mergerfs branches so disks aren't declared twice.
      # d1, d2, ... → each branch mountpoint (trailing slash required by snapraid).
      default = builtins.listToAttrs (lib.imap1 (i: b: {
        name = "d${toString i}";
        value = "${b.mountPoint}/";
      }) mergerfsBranches);
      defaultText = lib.literalExpression "derived from vexos.server.storage.mergerfs.branches";
      description = "SnapRAID data disks. Defaults to the mergerfs content disks.";
    };

    parityDisks = lib.mkOption {
      type = lib.types.listOf parityModule;
      default = [ ];
      description = ''
        Dedicated parity disks (NOT part of the mergerfs union). Each must be
        >= the largest content disk. Up to 6 (tolerating up to 6 simultaneous
        content-disk failures). Populated by `just create-mergerfs-pool`.
      '';
    };

    syncInterval = lib.mkOption {
      type = lib.types.str;
      default = "daily";
      description = "systemd OnCalendar schedule for `snapraid sync` (parity refresh).";
    };

    scrubInterval = lib.mkOption {
      type = lib.types.str;
      default = "weekly";
      description = "systemd OnCalendar schedule for `snapraid scrub` (bit-rot check).";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.dataDisks != { };
        message = ''
          vexos.server.storage.snapraid.enable = true but no data disks are
          defined. Enable mergerfs (which provides the content disks) or set
          vexos.server.storage.snapraid.dataDisks explicitly.
        '';
      }
      {
        assertion = cfg.parityDisks != [ ];
        message = ''
          vexos.server.storage.snapraid.enable = true but no parity disks are
          defined. SnapRAID needs at least one parity disk >= the largest
          content disk. Run `just create-mergerfs-pool`.
        '';
      }
    ];

    fileSystems = parityFileSystems;

    services.snapraid = {
      enable = true;
      dataDisks = cfg.dataDisks;
      parityFiles = lib.imap1 (i: p: "${p.mountPoint}/${parityFileName i}") cfg.parityDisks;
      # Content files live on every data AND parity disk for redundancy (PMS
      # practice) — a lost disk never takes the only copy of the file list.
      contentFiles =
        (lib.mapAttrsToList (_: d: "${d}snapraid.content") cfg.dataDisks)
        ++ (map (p: "${p.mountPoint}/snapraid.content") cfg.parityDisks);
      sync.interval = cfg.syncInterval;
      scrub.interval = cfg.scrubInterval;
    };

    # Route sync/scrub failures to ntfy via the generic notify template.
    systemd.services.snapraid-sync.onFailure = [ "notify-failure@snapraid-sync.service" ];
    systemd.services.snapraid-scrub.onFailure = [ "notify-failure@snapraid-scrub.service" ];
  };
}
