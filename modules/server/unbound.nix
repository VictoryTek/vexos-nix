# modules/server/unbound.nix
# Unbound — validating, recursive, caching DNS resolver.
# ⚠ Port 53 conflicts with AdGuard Home (adguard) — enable only one DNS service.
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

    networking.firewall.allowedTCPPorts = [ 53 ];
    networking.firewall.allowedUDPPorts = [ 53 ];
  };
}
