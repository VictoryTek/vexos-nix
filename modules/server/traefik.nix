# modules/server/traefik.nix
# Traefik — cloud-native reverse proxy with automatic Let's Encrypt.
# Configure providers and routes via services.traefik.dynamicConfigOptions in server-services.nix.
# Note: Caddy (also available) is simpler for basic setups — prefer Traefik for Docker label routing.
#
# Dashboard security:
#   insecureDashboard defaults to false — the dashboard/API is NOT accessible on dashboardPort.
#   To enable the dashboard for local troubleshooting:
#     vexos.server.traefik.insecureDashboard = true;
#   ⚠ The insecure dashboard exposes a read/write API. Never enable it on internet-facing hosts.
#     Use a basic-auth middleware or Traefik's secure-API mode instead for permanent access.
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
      description = "Port for the Traefik dashboard when insecureDashboard = true.";
    };

    insecureDashboard = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Expose the Traefik dashboard/API on dashboardPort without authentication
        (api.insecure = true). Disabled by default — the dashboard is a read/write
        API that must not be exposed on internet-facing hosts without additional
        authentication middleware.
        Enable only for local debugging on isolated LANs.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.traefik = {
      enable = true;
      staticConfigOptions = {
        api = {
          dashboard = true;
          insecure = cfg.insecureDashboard;
        };
        entryPoints = {
          web.address      = ":${toString cfg.httpPort}";
          websecure.address = ":${toString cfg.httpsPort}";
        } // lib.optionalAttrs cfg.insecureDashboard {
          traefik.address  = ":${toString cfg.dashboardPort}";
        };
        log.level = "INFO";
      };
    };

    # Only open the dashboard port when the insecure dashboard is explicitly enabled.
    networking.firewall.allowedTCPPorts =
      [ cfg.httpPort cfg.httpsPort ]
      ++ lib.optional cfg.insecureDashboard cfg.dashboardPort;
  };
}
