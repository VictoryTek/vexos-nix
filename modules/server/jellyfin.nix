# modules/server/jellyfin.nix
# Jellyfin media server — free software alternative to Plex.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.jellyfin;
  storageMounts = import ../lib/storage-mount-ordering.nix { inherit lib; };
in
{
  options.vexos.server.jellyfin = {
    enable = lib.mkEnableOption "Jellyfin media server";

    hardwareAcceleration = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable hardware acceleration permissions for Jellyfin.";
    };

    mediaMounts = storageMounts.mediaMountsOption;
  };

  config = lib.mkIf cfg.enable {
    services.jellyfin = {
      enable = true;
      openFirewall = true;
    };

    systemd.services.jellyfin.serviceConfig = lib.mkIf cfg.hardwareAcceleration {
      SupplementaryGroups = [ "render" "video" ];
    };

    # Order Jellyfin after its media storage is ready — local (mergerfs/ZFS)
    # or remote (storage-remote.nix, automount-based). See mediaMounts above.
    systemd.services.jellyfin.unitConfig = storageMounts.requiresMountsFor cfg.mediaMounts;

    # Allow the primary user to manage media directories alongside the jellyfin user.
    users.users.${config.vexos.user.name}.extraGroups = [ "jellyfin" ];
  };
}
