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

    qbittorrent.enable = lib.mkEnableOption "qBittorrent torrent client (part of the arr stack)";
    bazarr.enable = lib.mkEnableOption "Bazarr subtitle manager (part of the arr stack)";
  };

  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = cfg.enable || !cfg.qbittorrent.enable;
          message = "vexos.server.arr.qbittorrent.enable requires vexos.server.arr.enable = true.";
        }
        {
          assertion = cfg.enable || !cfg.bazarr.enable;
          message = "vexos.server.arr.bazarr.enable requires vexos.server.arr.enable = true.";
        }
      ];
    }
    (lib.mkIf cfg.enable {
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

      services.qbittorrent = lib.mkIf cfg.qbittorrent.enable {
        enable = true;
        openFirewall = true;
        webuiPort = 8081; # 8080 is SABnzbd's default; shifted to avoid conflict
        torrentingPort = 6881; # conventional BitTorrent port; fixed so openFirewall has a real port to open
      };

      services.bazarr = lib.mkIf cfg.bazarr.enable {
        enable = true;
        openFirewall = true; # Port 6767
      };

      users.users.${config.vexos.user.name}.extraGroups =
        [ "sabnzbd" "sonarr" "radarr" "lidarr" ]
        ++ lib.optional cfg.qbittorrent.enable "qbittorrent"
        ++ lib.optional cfg.bazarr.enable "bazarr";
    })
  ];
}
