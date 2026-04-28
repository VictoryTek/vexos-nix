# modules/server/prometheus.nix
# Prometheus — time-series metrics collection and alerting.
# Pair with Grafana (enable separately) for dashboards.
# ⚠ Default port 9090 conflicts with Cockpit — adjust cockpit.port if both are needed.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.prometheus;
in
{
  options.vexos.server.prometheus = {
    enable = lib.mkEnableOption "Prometheus metrics collection";

    port = lib.mkOption {
      type = lib.types.port;
      default = 9090;
      description = "Port for the Prometheus web UI and API. ⚠ Conflicts with Cockpit on port 9090.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.prometheus = {
      enable = true;
      port = cfg.port;
    };

    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
