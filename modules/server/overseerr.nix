# modules/server/overseerr.nix
# Overseerr — media request management for Plex.
# Note: Overseerr and Jellyseerr both default to port 5055 — enable only one.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.overseerr;
in
{
  options.vexos.server.overseerr = {
    enable = lib.mkEnableOption "Overseerr media request manager";

    port = lib.mkOption {
      type    = lib.types.port;
      default = 5055;
      description = "Port Overseerr listens on. Change if co-hosting with Jellyseerr.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.overseerr = {
      enable      = true;
      openFirewall = true;
      port        = cfg.port;
    };
  };
}
