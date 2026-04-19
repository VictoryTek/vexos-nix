# modules/server/overseerr.nix
# Overseerr — media request management for Plex.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.overseerr;
in
{
  options.vexos.server.overseerr = {
    enable = lib.mkEnableOption "Overseerr media request manager";
  };

  config = lib.mkIf cfg.enable {
    services.overseerr = {
      enable = true;
      openFirewall = true; # Default port: 5055
    };
  };
}
