# modules/server/immich.nix
# Immich — self-hosted photo and video backup (Google Photos alternative).
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.immich;
  storageMounts = import ../lib/storage-mount-ordering.nix { inherit lib; };
in
{
  options.vexos.server.immich = {
    enable = lib.mkEnableOption "Immich photo/video backup server";

    port = lib.mkOption {
      type = lib.types.port;
      default = 2283;
      description = "Port for the Immich web interface.";
    };

    mediaMounts = storageMounts.mediaMountsOption;
  };

  config = lib.mkIf cfg.enable {
    services.immich = {
      enable = true;
      port = cfg.port;
      openFirewall = true;
    };

    # Order immich-server (the unit that actually reads/writes the photo
    # library) after its storage — local (mergerfs/ZFS) or remote
    # (storage-remote.nix, automount-based). immich-machine-learning is a
    # pure HTTP inference worker and never touches the library path itself,
    # so it's intentionally not ordered here.
    systemd.services.immich-server.unitConfig = storageMounts.requiresMountsFor cfg.mediaMounts;
  };
}
