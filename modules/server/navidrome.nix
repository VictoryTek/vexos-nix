# modules/server/navidrome.nix
# Navidrome — self-hosted music streaming (Subsonic/Airsonic API compatible).
# Compatible clients: DSub, Symfonium, Substreamer, Feishin, Sonixd.
# Default port: 4533
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.navidrome;
  storageMounts = import ../lib/storage-mount-ordering.nix { inherit lib; };
in
{
  options.vexos.server.navidrome = {
    enable = lib.mkEnableOption "Navidrome music streaming server";

    mediaMounts = storageMounts.mediaMountsOption;

    port = lib.mkOption {
      type = lib.types.port;
      default = 4533;
      description = "Port for the Navidrome web interface.";
    };

    musicFolder = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/navidrome/music";
      description = "Path to the music library folder.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open the firewall for Navidrome's port.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.navidrome = {
      enable = true;
      settings = {
        Address = "0.0.0.0";
        Port = cfg.port;
        MusicFolder = cfg.musicFolder;
      };
    };

    networking.firewall.allowedTCPPorts = lib.optional cfg.openFirewall cfg.port;

    # Order Navidrome after its music storage is ready — local (mergerfs/ZFS)
    # or remote (storage-remote.nix, automount-based). See mediaMounts above.
    systemd.services.navidrome.unitConfig = storageMounts.requiresMountsFor cfg.mediaMounts;
  };
}
