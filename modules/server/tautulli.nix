# modules/server/tautulli.nix
# Tautulli — monitoring and analytics for Plex Media Server.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.tautulli;
in
{
  options.vexos.server.tautulli = {
    enable = lib.mkEnableOption "Tautulli Plex analytics";
  };

  config = lib.mkIf cfg.enable {
    services.tautulli = {
      enable = true;
      openFirewall = true; # Default port: 8181
    };
  };
}
