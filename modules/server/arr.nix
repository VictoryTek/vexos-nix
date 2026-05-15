# modules/server/arr.nix
# Arr Stack — SABnzbd + Sonarr + Radarr + Lidarr + Prowlarr for media automation.
# Note: Readarr is retired upstream. Use the bookshelf fork via Docker if needed.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.arr;
in
{
  options.vexos.server.arr = {
    enable = lib.mkEnableOption "Arr stack (SABnzbd, Sonarr, Radarr, Lidarr, Prowlarr)";
  };

  config = lib.mkIf cfg.enable {
    services.sabnzbd = {
      enable = true;
      openFirewall = true; # Port 8080
    };

    services.sonarr = {
      enable = true;
      openFirewall = true; # Port 8989
    };

    services.radarr = {
      enable = true;
      openFirewall = true; # Port 7878
    };

    services.lidarr = {
      enable = true;
      openFirewall = true; # Port 8686
    };

    services.prowlarr = {
      enable = true;
      openFirewall = true; # Port 9696
    };

    users.users.${config.vexos.user.name}.extraGroups = [ "sabnzbd" "sonarr" "radarr" "lidarr" ];
  };
}
