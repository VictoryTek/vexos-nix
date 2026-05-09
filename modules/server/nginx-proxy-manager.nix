# modules/server/nginx-proxy-manager.nix
# Nginx Proxy Manager — web GUI for managing Nginx reverse proxy rules (OCI container).
# Admin UI port: 81  |  HTTP proxy: 8881  |  HTTPS proxy: 8444
# Ports remapped from 80/443 to avoid conflicts with nginx, caddy, and traefik.
# Default login: admin@example.com / changeme — change immediately after first login.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.nginx-proxy-manager;
in
{
  options.vexos.server.nginx-proxy-manager = {
    enable = lib.mkEnableOption "Nginx Proxy Manager reverse proxy UI";

    httpPort = lib.mkOption {
      type = lib.types.port;
      default = 8881;
      description = "Host port for HTTP proxy traffic.";
    };

    httpsPort = lib.mkOption {
      type = lib.types.port;
      default = 8444;
      description = "Host port for HTTPS proxy traffic.";
    };

    adminPort = lib.mkOption {
      type = lib.types.port;
      default = 81;
      description = "Port for the Nginx Proxy Manager admin interface.";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.docker.enable = lib.mkDefault true;
    virtualisation.oci-containers.backend = "docker";

    virtualisation.oci-containers.containers.nginx-proxy-manager = {
      image = "jc21/nginx-proxy-manager:latest";
      ports = [
        "${toString cfg.httpPort}:80"
        "${toString cfg.httpsPort}:443"
        "${toString cfg.adminPort}:81"
      ];
      volumes = [
        "npm-data:/data"
        "npm-letsencrypt:/etc/letsencrypt"
      ];
    };

    networking.firewall.allowedTCPPorts = [ cfg.httpPort cfg.httpsPort cfg.adminPort ];
  };
}
