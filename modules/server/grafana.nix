# modules/server/grafana.nix
# Grafana — metrics and observability dashboards.
# Pair with Prometheus (enable separately) for full monitoring stack.
# Default port: 3030
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.grafana;
in
{
  options.vexos.server.grafana = {
    enable = lib.mkEnableOption "Grafana observability dashboards";

    port = lib.mkOption {
      type = lib.types.port;
      default = 3030;
      description = "Port for the Grafana web UI.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.grafana = {
      enable = true;
      settings.server = {
        http_addr = "0.0.0.0";
        http_port = cfg.port;
        domain = "localhost";
      };
    };

    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
