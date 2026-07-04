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

    serverUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://headscale.example.com";
      description = ''
        Public URL that Tailscale clients connect to directly — must be a real,
        externally-reachable address (e.g. "https://headscale.example.com" or
        "http://192.168.1.50:8085"), never a bind address like 0.0.0.0. The
        default placeholder is intentionally invalid.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.serverUrl != "https://headscale.example.com";
        message = ''
          vexos.server.headscale.serverUrl must be set to the actual public URL
          clients will connect to (e.g. "https://headscale.example.com" or
          "http://192.168.1.50:8085"). Every Tailscale client receives this URL
          and tries to connect to it directly, so it cannot be a bind address.
        '';
      }
    ];

    services.headscale = {
      enable = true;
      port = cfg.port;
      settings = {
        server_url = cfg.serverUrl;
        metrics_listen_addr = "127.0.0.1:9093";
        log.level = "info";
      };
    };

    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
