# modules/server/loki.nix
# Loki — log aggregation system (Grafana stack).
# Pair with Grafana for log visualization. Ships logs via Promtail or Alloy agents.
# Default port: 3100
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.loki;
in
{
  options.vexos.server.loki = {
    enable = lib.mkEnableOption "Loki log aggregation";
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

    networking.firewall.allowedTCPPorts = [ 3100 ];
  };
}
