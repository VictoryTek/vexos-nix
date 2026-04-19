# modules/server/plex.nix
# Plex Media Server — proprietary streaming media server.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.plex;
in
{
  options.vexos.server.plex = {
    enable = lib.mkEnableOption "Plex Media Server";
  };

  config = lib.mkIf cfg.enable {
    services.plex = {
      enable = true;
      openFirewall = true;
    };

    users.users.nimda.extraGroups = [ "plex" ];
  };
}
