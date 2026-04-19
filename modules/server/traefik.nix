# modules/server/traefik.nix
# Traefik — cloud-native reverse proxy with automatic Let's Encrypt.
# Configure providers and routes via services.traefik.dynamicConfigOptions in server-services.nix.
# Note: Caddy (also available) is simpler for basic setups — prefer Traefik for Docker label routing.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.traefik;
in
{
  options.vexos.server.traefik = {
    enable = lib.mkEnableOption "Traefik reverse proxy";
  };

  config = lib.mkIf cfg.enable {
    services.traefik = {
      enable = true;
      staticConfigOptions = {
        api = {
          dashboard = true;
          insecure = true; # Dashboard on port 8080; restrict or disable in production
        };
        entryPoints = {
          web.address = ":80";
          websecure.address = ":443";
        };
        log.level = "INFO";
      };
    };

    # 80/443 for proxied traffic; 8080 for the Traefik dashboard
    networking.firewall.allowedTCPPorts = [ 80 443 8080 ];
  };
}
