# modules/lib/storage-mount-ordering.nix
# Shared helper: lets a storage-consuming service module (Plex, Jellyfin,
# Immich, Nextcloud, ...) order its systemd unit(s) after the mount(s)
# backing its data/library — local (mergerfs/ZFS) or remote
# (vexos.server.storage.remote, automount-based) — instead of racing a mount
# that isn't ready yet and starting against an empty/missing path.
#
# Usage in a service module:
#   storageMounts = import ../lib/storage-mount-ordering.nix { inherit lib; };
#   options.vexos.server.<svc>.mediaMounts = storageMounts.mediaMountsOption;
#   config.systemd.services.<unit>.unitConfig =
#     storageMounts.requiresMountsFor cfg.mediaMounts;
#
# Apply to every systemd unit that actually reads/writes the mount (verified
# per-service — not every unit a service defines touches its data path, e.g.
# Immich's machine-learning worker only receives image bytes over HTTP and
# never touches the library path itself).
{ lib }:
{
  mediaMountsOption = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    example = [ "/mnt/nas-media" ];
    description = ''
      Absolute mountpoint(s) this service's data/library lives under — a
      local pool (mergerfs/ZFS, e.g. "/storage") or a remote NAS mount from
      vexos.server.storage.remote (e.g. "/mnt/nas-media").

      Orders the service's systemd unit(s) after that storage via
      RequiresMountsFor, so it waits for (and, for automount-based remote
      mounts, correctly triggers) the mount instead of starting against an
      empty/missing path. Leave empty for hosts with no pooled/remote
      storage dependency for this service.
    '';
  };

  requiresMountsFor = mounts:
    lib.mkIf (mounts != [ ]) {
      RequiresMountsFor = lib.concatStringsSep " " mounts;
    };
}
