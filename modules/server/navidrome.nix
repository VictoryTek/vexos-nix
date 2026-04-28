# modules/server/navidrome.nix
# Navidrome — self-hosted music streaming (Subsonic/Airsonic API compatible).
# Compatible clients: DSub, Symfonium, Substreamer, Feishin, Sonixd.
# Default port: 4533
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.navidrome;
in
{
  options.vexos.server.navidrome = {
    enable = lib.mkEnableOption "Navidrome music streaming server";

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

    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
