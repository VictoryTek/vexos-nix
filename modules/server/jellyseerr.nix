# modules/server/jellyseerr.nix
# Jellyseerr — media request management for Jellyfin/Emby/Plex.
# Note: Jellyseerr and Overseerr both default to port 5055 — enable only one.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.jellyseerr;
in
{
  options.vexos.server.jellyseerr = {
    enable = lib.mkEnableOption "Jellyseerr media request manager";

    port = lib.mkOption {
      type    = lib.types.port;
      default = 5055;
      description = "Port Jellyseerr listens on. Change if co-hosting with Overseerr.";
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
