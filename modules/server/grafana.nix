# modules/server/grafana.nix
# Grafana — metrics and observability dashboards.
# Pair with Prometheus (enable separately) for full monitoring stack.
# Default port: 3030
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.grafana;
  prometheusEnabled = config.vexos.server.prometheus.enable;
  lokiEnabled = config.vexos.server.loki.enable;
  fluentBitEnabled = config.vexos.server.fluent-bit.enable;

  # Node Exporter Full (grafana.com dashboard 1860, revision 45) — auto-resolves
  # its Prometheus datasource variable to whichever prometheus-type datasource
  # is configured, so no manual UID substitution is needed here.
  nodeExporterDashboard = pkgs.fetchurl {
    url = "https://grafana.com/api/dashboards/1860/revisions/45/download";
    sha256 = "sha256-GExrdAnzBtp1Ul13cvcZRbEM6iOtFrXXjEaY6g6lGYY=";
  };

  dashboardsDir = pkgs.runCommand "vexos-grafana-dashboards" { } (''
    mkdir -p $out
  ''
  + lib.optionalString prometheusEnabled ''
    cp ${nodeExporterDashboard} $out/node-exporter-full.json
  ''
  + lib.optionalString fluentBitEnabled ''
    cp ${./grafana-dashboards/systemd-journal.json} $out/systemd-journal.json
  '');
in
{
  options.vexos.server.grafana = {
    enable = lib.mkEnableOption "Grafana observability dashboards";

    port = lib.mkOption {
      type = lib.types.port;
      default = 3030;
      description = "Port for the Grafana web UI.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open the firewall for Grafana's port.";
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
    }
    // lib.optionalAttrs (prometheusEnabled || lokiEnabled) {
      provision = {
        enable = true;
        datasources.settings = {
          apiVersion = 1;
          datasources =
            lib.optional prometheusEnabled {
              name = "Prometheus";
              type = "prometheus";
              access = "proxy";
              url = "http://localhost:${toString config.vexos.server.prometheus.port}";
              editable = false;
            }
            ++ lib.optional lokiEnabled {
              name = "Loki";
              type = "loki";
              uid = "loki";
              access = "proxy";
              url = "http://localhost:3100";
              editable = false;
            };
        };
        dashboards.settings = lib.mkIf (prometheusEnabled || fluentBitEnabled) {
          apiVersion = 1;
          providers = [
            {
              name = "vexos";
              options.path = dashboardsDir;
            }
          ];
        };
      };
    };

    networking.firewall.allowedTCPPorts = lib.optional cfg.openFirewall cfg.port;
  };
}
