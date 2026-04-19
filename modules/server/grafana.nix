# modules/server/grafana.nix
# Grafana — metrics and observability dashboards.
# Pair with Prometheus (enable separately) for full monitoring stack.
# Default port: 3000
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.grafana;
in
{
  options.vexos.server.grafana = {
    enable = lib.mkEnableOption "Grafana observability dashboards";
  };

  config = lib.mkIf cfg.enable {
    services.grafana = {
      enable = true;
      settings.server = {
        http_addr = "0.0.0.0";
        http_port = 3000;
        domain = "localhost";
      };
    };

    networking.firewall.allowedTCPPorts = [ 3000 ];
  };
}
