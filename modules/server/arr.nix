# modules/server/arr.nix
# Arr Stack — Sonarr + Radarr + Prowlarr for media automation.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.arr;
in
{
  options.vexos.server.arr = {
    enable = lib.mkEnableOption "Arr stack (Sonarr, Radarr, Prowlarr)";
  };

  config = lib.mkIf cfg.enable {
    services.sonarr = {
      enable = true;
      openFirewall = true; # Port 8989
    };

    services.radarr = {
      enable = true;
      openFirewall = true; # Port 7878
    };

    services.prowlarr = {
      enable = true;
      openFirewall = true; # Port 9696
    };

    users.users.nimda.extraGroups = [ "sonarr" "radarr" ];
  };
}
