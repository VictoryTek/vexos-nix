# modules/server/traefik.nix
# Traefik — cloud-native reverse proxy with automatic Let's Encrypt.
# Configure providers and routes via services.traefik.dynamicConfigOptions in server-services.nix.
# Note: Caddy (also available) is simpler for basic setups — prefer Traefik for Docker label routing.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.traefik;
in
{
  options.vexos.server.traefik = {
    enable = lib.mkEnableOption "Traefik reverse proxy";

    httpPort = lib.mkOption {
      type = lib.types.port;
      default = 8882;
      description = "Port for the Traefik HTTP entrypoint.";
    };

    httpsPort = lib.mkOption {
      type = lib.types.port;
      default = 8445;
      description = "Port for the Traefik HTTPS entrypoint.";
    };

    dashboardPort = lib.mkOption {
      type = lib.types.port;
      default = 8079;
      description = "Port for the Traefik dashboard (insecure API).";
    };
  };

  config = lib.mkIf cfg.enable {
    services.traefik = {
      enable = true;
      staticConfigOptions = {
        api = {
          dashboard = true;
          insecure = true; # Dashboard on dashboardPort; restrict or disable in production
        };
        entryPoints = {
          web.address = ":${toString cfg.httpPort}";
          websecure.address = ":${toString cfg.httpsPort}";
          traefik.address = ":${toString cfg.dashboardPort}";
        };
        log.level = "INFO";
      };
    };

    networking.firewall.allowedTCPPorts = [ cfg.httpPort cfg.httpsPort cfg.dashboardPort ];
  };
}
