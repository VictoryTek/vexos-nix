# modules/server/unbound.nix
# Unbound — validating, recursive, caching DNS resolver.
# Uses port 5353 to avoid conflict with AdGuard Home (port 53).
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.unbound;
in
{
  options.vexos.server.unbound = {
    enable = lib.mkEnableOption "Unbound local DNS resolver";
  };

  config = lib.mkIf cfg.enable {
    services.unbound = {
      enable = true;
      settings = {
        server = {
          interface = [ "0.0.0.0" "::" ];
          port = 5353;
          access-control = [
            "127.0.0.0/8 allow"
            "10.0.0.0/8 allow"
            "172.16.0.0/12 allow"
            "192.168.0.0/16 allow"
          ];
          hide-identity = true;
          hide-version = true;
        };
      };
    };

    networking.firewall.allowedTCPPorts = [ 5353 ];
    networking.firewall.allowedUDPPorts = [ 5353 ];
  };
}
