# modules/server/prometheus.nix
# Prometheus — time-series metrics collection and alerting.
# Pair with Grafana (enable separately) for dashboards.
# ⚠ Default port 9090 conflicts with Cockpit — Prometheus uses 9092 to avoid conflict.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.prometheus;
in
{
  options.vexos.server.prometheus = {
    enable = lib.mkEnableOption "Prometheus metrics collection";

    port = lib.mkOption {
      type = lib.types.port;
      default = 9092;
      description = "Port for the Prometheus web UI and API.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.prometheus = {
      enable = true;
      port = cfg.port;

      exporters.node = {
        enable = true;
        openFirewall = false;
        port = 9100;
      };

      scrapeConfigs = [
        {
          job_name = "node";
          static_configs = [
            {
              targets = [ "localhost:${toString config.services.prometheus.exporters.node.port}" ];
            }
          ];
        }
      ];
    };

    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
