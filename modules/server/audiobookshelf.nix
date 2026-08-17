# modules/server/audiobookshelf.nix
# Audiobookshelf — self-hosted audiobook and podcast server.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.audiobookshelf;
  storageMounts = import ../lib/storage-mount-ordering.nix { inherit lib; };
in
{
  options.vexos.server.audiobookshelf = {
    enable = lib.mkEnableOption "Audiobookshelf audiobook server";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8234;
      description = "Port for the Audiobookshelf web interface.";
    };

    mediaMounts = storageMounts.mediaMountsOption;
  };

  config = lib.mkIf cfg.enable {
    services.audiobookshelf = {
      enable = true;
      port = cfg.port;
      openFirewall = true;
    };

    # Order Audiobookshelf after its library storage is ready — local
    # (mergerfs/ZFS) or remote (storage-remote.nix, automount-based). See
    # mediaMounts above.
    systemd.services.audiobookshelf.unitConfig = storageMounts.requiresMountsFor cfg.mediaMounts;
  };
}
