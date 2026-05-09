# modules/server/nginx.nix
# Nginx — high-performance web server and reverse proxy.
# Configure virtual hosts in /etc/nixos/server-services.nix or a separate module.
# Note: Caddy (also available) handles certificates automatically — prefer it for simple setups.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.nginx;
in
{
  options.vexos.server.nginx = {
    enable = lib.mkEnableOption "Nginx web server";

    httpPort = lib.mkOption {
      type = lib.types.port;
      default = 80;
      description = "Default HTTP listen port for Nginx virtual hosts.";
    };

    httpsPort = lib.mkOption {
      type = lib.types.port;
      default = 443;
      description = "Default HTTPS listen port for Nginx virtual hosts.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.nginx = {
      enable = true;
      defaultHTTPListenPort = cfg.httpPort;
      defaultSSLListenPort = cfg.httpsPort;
      recommendedGzipSettings = true;
      recommendedOptimisation = true;
      recommendedProxySettings = true;
      recommendedTlsSettings = true;
    };

    networking.firewall.allowedTCPPorts = [ cfg.httpPort cfg.httpsPort ];
  };
}
