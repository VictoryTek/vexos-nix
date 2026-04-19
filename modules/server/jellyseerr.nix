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
  };

  config = lib.mkIf cfg.enable {
    services.jellyseerr = {
      enable = true;
      openFirewall = true; # Default port: 5055
    };
  };
}
