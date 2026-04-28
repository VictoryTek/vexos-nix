# modules/server/nginx-proxy-manager.nix
# Nginx Proxy Manager — web GUI for managing Nginx reverse proxy rules (OCI container).
# Admin UI port: 81  |  HTTP proxy: 80  |  HTTPS proxy: 443
# ⚠ Ports 80 and 443 conflict with nginx, caddy, and traefik — enable only one reverse proxy.
# Default login: admin@example.com / changeme — change immediately after first login.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.nginx-proxy-manager;
in
{
  options.vexos.server.nginx-proxy-manager = {
    enable = lib.mkEnableOption "Nginx Proxy Manager reverse proxy UI";

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
        "80:80"
        "443:443"
        "${toString cfg.adminPort}:81"
      ];
      volumes = [
        "npm-data:/data"
        "npm-letsencrypt:/etc/letsencrypt"
      ];
    };

    networking.firewall.allowedTCPPorts = [ 80 443 cfg.adminPort ];
  };
}
