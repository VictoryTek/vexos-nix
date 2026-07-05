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
        enabledCollectors = [ "systemd" ];
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

      rules = lib.optional config.vexos.server.alertmanager.enable (builtins.toJSON {
        groups = [
          {
            name = "vexos-node";
            rules = [
              {
                alert = "NodeDown";
                expr = "up{job=\"node\"} == 0";
                for = "5m";
                labels.severity = "critical";
                annotations = {
                  summary = "Node exporter target down";
                  description = "Prometheus has not been able to scrape the node exporter for 5 minutes.";
                };
              }
              {
                alert = "NodeFilesystemAlmostFull";
                expr = "node_filesystem_avail_bytes{fstype!~\"tmpfs|overlay\"} / node_filesystem_size_bytes{fstype!~\"tmpfs|overlay\"} < 0.1";
                for = "15m";
                labels.severity = "warning";
                annotations = {
                  summary = "Filesystem {{ $labels.mountpoint }} almost full";
                  description = "Less than 10% free space remaining on {{ $labels.mountpoint }}.";
                };
              }
              {
                alert = "SystemdUnitFailed";
                expr = "node_systemd_unit_state{state=\"failed\"} == 1";
                for = "5m";
                labels.severity = "warning";
                annotations = {
                  summary = "systemd unit {{ $labels.name }} failed";
                  description = "systemd unit {{ $labels.name }} has been in the failed state for 5 minutes.";
                };
              }
            ];
          }
        ];
      });

      alertmanagers = lib.optional config.vexos.server.alertmanager.enable {
        static_configs = [
          { targets = [ "localhost:${toString config.vexos.server.alertmanager.port}" ]; }
        ];
      };
    };

    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
