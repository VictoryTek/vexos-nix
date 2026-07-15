# modules/server/arr.nix
# Arr Stack — SABnzbd + Sonarr + Radarr + Lidarr + Prowlarr for media automation,
# plus Maintainerr for automated library cleanup.
# Note: Readarr is retired upstream. Use the bookshelf fork via Docker if needed.
# Each core service has its own enable flag so it can be turned on individually;
# vexos.server.arr.enable is a convenience meta-flag that defaults all five on.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.arr;
in
{
  options.vexos.server.arr = {
    enable = lib.mkEnableOption "Arr stack (SABnzbd, Sonarr, Radarr, Lidarr, Prowlarr) — enables all core services";

    sabnzbd.enable = lib.mkEnableOption "SABnzbd Usenet downloader (part of the arr stack)";
    sonarr.enable = lib.mkEnableOption "Sonarr TV management (part of the arr stack)";
    radarr.enable = lib.mkEnableOption "Radarr movie management (part of the arr stack)";
    lidarr.enable = lib.mkEnableOption "Lidarr music management (part of the arr stack)";
    prowlarr.enable = lib.mkEnableOption "Prowlarr indexer manager (part of the arr stack)";
    qbittorrent.enable = lib.mkEnableOption "qBittorrent torrent client (part of the arr stack)";
    bazarr.enable = lib.mkEnableOption "Bazarr subtitle manager (part of the arr stack)";

    maintainerr.enable = lib.mkEnableOption "Maintainerr automated library cleanup (part of the arr stack)";
    maintainerr.port = lib.mkOption {
      type = lib.types.port;
      default = 6246;
      description = "Port Maintainerr's web UI listens on.";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      vexos.server.arr.sabnzbd.enable = lib.mkDefault true;
      vexos.server.arr.sonarr.enable = lib.mkDefault true;
      vexos.server.arr.radarr.enable = lib.mkDefault true;
      vexos.server.arr.lidarr.enable = lib.mkDefault true;
      vexos.server.arr.prowlarr.enable = lib.mkDefault true;
    })

    (lib.mkIf cfg.sabnzbd.enable {
      services.sabnzbd = {
        enable = true;
        openFirewall = true; # Port 8080
        configFile = null; # use the settings-based config path (configFile is deprecated)
        settings.misc.host = "0.0.0.0"; # module default is 127.0.0.1, which would make openFirewall pointless
      };
    })

    (lib.mkIf cfg.sonarr.enable {
      services.sonarr = {
        enable = true;
        openFirewall = true; # Port 8989
      };
    })

    (lib.mkIf cfg.radarr.enable {
      services.radarr = {
        enable = true;
        openFirewall = true; # Port 7878
      };
    })

    (lib.mkIf cfg.lidarr.enable {
      services.lidarr = {
        enable = true;
        openFirewall = true; # Port 8686
      };
    })

    (lib.mkIf cfg.prowlarr.enable {
      services.prowlarr = {
        enable = true;
        openFirewall = true; # Port 9696
      };
    })

    (lib.mkIf cfg.qbittorrent.enable {
      services.qbittorrent = {
        enable = true;
        openFirewall = true;
        webuiPort = 8081; # 8080 is SABnzbd's default; shifted to avoid conflict
        torrentingPort = 6881; # conventional BitTorrent port; fixed so openFirewall has a real port to open
      };
    })

    (lib.mkIf cfg.bazarr.enable {
      services.bazarr = {
        enable = true;
        openFirewall = true; # Port 6767
      };
    })

    (lib.mkIf cfg.maintainerr.enable {
      virtualisation.docker.enable = lib.mkDefault true;
      virtualisation.oci-containers.backend = lib.mkDefault "docker";

      virtualisation.oci-containers.containers.maintainerr = {
        image = "ghcr.io/maintainerr/maintainerr:3.17.1";
        ports = [ "${toString cfg.maintainerr.port}:6246" ];
        volumes = [ "maintainerr-data:/opt/data" ];
        environment = { TZ = config.time.timeZone; };
      };

      networking.firewall.allowedTCPPorts = [ cfg.maintainerr.port ];
    })

    {
      users.users.${config.vexos.user.name}.extraGroups =
        lib.optional cfg.sabnzbd.enable "sabnzbd"
        ++ lib.optional cfg.sonarr.enable "sonarr"
        ++ lib.optional cfg.radarr.enable "radarr"
        ++ lib.optional cfg.lidarr.enable "lidarr"
        ++ lib.optional cfg.qbittorrent.enable "qbittorrent"
        ++ lib.optional cfg.bazarr.enable "bazarr";
    }
  ];
}
