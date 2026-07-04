# modules/server/loki.nix
# Loki — log aggregation system (Grafana stack).
# Pair with Grafana for log visualization. Ships logs via Promtail or Alloy agents.
# Default port: 3100
# ⚠ auth_enabled = false — Loki has no authentication of its own. Anyone who can
#   reach the port can read and write logs. Set openFirewall = false to restrict
#   access to localhost/VPN only.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.loki;
in
{
  options.vexos.server.loki = {
    enable = lib.mkEnableOption "Loki log aggregation";

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Open the firewall for Loki's port. Defaults to true — Loki is intended
        to receive logs from other machines on the LAN. It has no
        authentication of its own; set to false to restrict access to
        localhost/VPN only.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.loki = {
      enable = true;
      configuration = {
        auth_enabled = false;

        server.http_listen_port = 3100;

        ingester = {
          lifecycler = {
            ring = {
              kvstore.store = "inmemory";
              replication_factor = 1;
            };
            final_sleep = "0s";
          };
          chunk_idle_period = "5m";
          chunk_retain_period = "30s";
        };

        schema_config.configs = [{
          from = "2024-01-01";
          store = "tsdb";
          object_store = "filesystem";
          schema = "v13";
          index = {
            prefix = "index_";
            period = "24h";
          };
        }];

        storage_config = {
          tsdb_shipper = {
            active_index_directory = "/var/lib/loki/tsdb-active";
            cache_location = "/var/lib/loki/tsdb-cache";
          };
          filesystem.directory = "/var/lib/loki/chunks";
        };

        limits_config = {
          reject_old_samples = true;
          reject_old_samples_max_age = "168h";
        };

        compactor = {
          working_directory = "/var/lib/loki/compactor";
          retention_enabled = false;
        };
      };
    };

    networking.firewall.allowedTCPPorts = lib.optional cfg.openFirewall 3100;
  };
}
