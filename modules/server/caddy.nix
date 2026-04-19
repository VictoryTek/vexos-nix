# modules/server/caddy.nix
# Caddy — reverse proxy with automatic HTTPS.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.caddy;
in
{
  options.vexos.server.caddy = {
    enable = lib.mkEnableOption "Caddy reverse proxy";
  };

  config = lib.mkIf cfg.enable {
    services.caddy = {
      enable = true;
      # Virtual hosts are configured in /etc/nixos/server-services.nix
      # or via Caddy's JSON API.  Example:
      #   services.caddy.virtualHosts."jellyfin.local".extraConfig = ''
      #     reverse_proxy localhost:8096
      #   '';
    };

    networking.firewall.allowedTCPPorts = [ 80 443 ];
  };
}
