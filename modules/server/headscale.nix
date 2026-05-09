# modules/server/headscale.nix
# Headscale — self-hosted Tailscale control server (VPN mesh coordination).
# After enabling, use the headscale CLI to create users and generate auth keys.
# Default port: 8080 — adjust if it conflicts with other services.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.headscale;
in
{
  options.vexos.server.headscale = {
    enable = lib.mkEnableOption "Headscale Tailscale control server";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8085;
      description = "Port for the Headscale HTTP/gRPC listener.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.headscale = {
      enable = true;
      port = cfg.port;
      serverUrl = "http://0.0.0.0:${toString cfg.port}";
      settings = {
        metrics_listen_addr = "127.0.0.1:9093";
        log.level = "info";
      };
    };

    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
