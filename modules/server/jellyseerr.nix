# modules/server/jellyseerr.nix
# Jellyseerr — media request management for Jellyfin/Emby/Plex.
# Default port: 5056 (Seerr uses 5055).
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.jellyseerr;
in
{
  options.vexos.server.jellyseerr = {
    enable = lib.mkEnableOption "Jellyseerr media request manager";

    port = lib.mkOption {
      type    = lib.types.port;
      default = 5056;
      description = "Port Jellyseerr listens on.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.jellyseerr = {
      enable      = true;
      openFirewall = true;
      port        = cfg.port;
    };
  };
}
