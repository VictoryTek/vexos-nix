# modules/server/caddy.nix
# Caddy — reverse proxy with automatic HTTPS.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.caddy;
in
{
  options.vexos.server.caddy = {
    enable = lib.mkEnableOption "Caddy reverse proxy";

    httpPort = lib.mkOption {
      type = lib.types.port;
      default = 8880;
      description = "Port for Caddy HTTP listener.";
    };

    httpsPort = lib.mkOption {
      type = lib.types.port;
      default = 8443;
      description = "Port for Caddy HTTPS listener.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open the firewall for Caddy's HTTP/HTTPS ports.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.caddy = {
      enable = true;
      globalConfig = ''
        http_port  ${toString cfg.httpPort}
        https_port ${toString cfg.httpsPort}
      '';
      # Virtual hosts are configured in /etc/nixos/server-services.nix
      # or via Caddy's JSON API.  Example:
      #   services.caddy.virtualHosts."jellyfin.local".extraConfig = ''
      #     reverse_proxy localhost:8096
      #   '';
    };

    networking.firewall.allowedTCPPorts = lib.optionals cfg.openFirewall [ cfg.httpPort cfg.httpsPort ];
  };
}
