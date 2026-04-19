# modules/server/jellyfin.nix
# Jellyfin media server — free software alternative to Plex.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.jellyfin;
in
{
  options.vexos.server.jellyfin = {
    enable = lib.mkEnableOption "Jellyfin media server";
  };

  config = lib.mkIf cfg.enable {
    services.jellyfin = {
      enable = true;
      openFirewall = true;
    };

    # Allow nimda to manage media directories alongside the jellyfin user.
    users.users.nimda.extraGroups = [ "jellyfin" ];
  };
}
