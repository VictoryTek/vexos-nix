# modules/server/alertmanager.nix
# Prometheus Alertmanager — evaluates alerting rules and routes firing alerts
# to the existing self-hosted ntfy server (modules/server/ntfy.nix) via
# nixpkgs' own services.prometheus.alertmanager-ntfy bridge, which translates
# Alertmanager's fixed webhook JSON schema into a proper ntfy publish (topic,
# title, priority). Requires vexos.server.prometheus.enable — this module
# only evaluates rules against metrics Prometheus already scrapes (the node
# exporter enabled by prometheus.nix). Requires vexos.server.ntfy.enable —
# points alertmanager-ntfy at that local instance directly rather than
# vexos.notify.ntfyUrl, which bundles a specific topic into its URL and isn't
# shaped like the base-URL + topic split alertmanager-ntfy expects.
{ config, lib, ... }:
let
  cfg = config.vexos.server.alertmanager;
in
{
  options.vexos.server.alertmanager = {
    enable = lib.mkEnableOption "Prometheus Alertmanager with ntfy notifications";

    port = lib.mkOption {
      type = lib.types.port;
      default = 9093;
      description = "Port for the Alertmanager web UI and API.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open the firewall for Alertmanager's port.";
    };

    ntfyTopic = lib.mkOption {
      type = lib.types.str;
      default = "vexos-alerts";
      description = "ntfy topic that alert notifications are published to.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.vexos.server.prometheus.enable;
        message = "vexos.server.alertmanager.enable requires vexos.server.prometheus.enable = true — Alertmanager evaluates alerting rules against Prometheus's scraped metrics.";
      }
      {
        assertion = config.vexos.server.ntfy.enable;
        message = "vexos.server.alertmanager.enable requires vexos.server.ntfy.enable = true — alerts are delivered to the local ntfy instance.";
      }
    ];

    services.prometheus.alertmanager = {
      enable = true;
      port = cfg.port;
      openFirewall = cfg.openFirewall;
      configuration = {
        route = {
          receiver = "ntfy";
          group_by = [ "alertname" ];
          group_wait = "30s";
          group_interval = "5m";
          repeat_interval = "4h";
        };
        receivers = [
          {
            name = "ntfy";
            webhook_configs = [
              {
                url = "http://${config.services.prometheus.alertmanager-ntfy.settings.http.addr}/hook";
                send_resolved = true;
              }
            ];
          }
        ];
      };
    };

    services.prometheus.alertmanager-ntfy = {
      enable = true;
      settings = {
        ntfy = {
          baseurl = "http://localhost:${toString config.vexos.server.ntfy.port}";
          notification.topic = cfg.ntfyTopic;
        };
      };
    };
  };
}
