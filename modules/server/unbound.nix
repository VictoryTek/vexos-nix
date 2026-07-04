# modules/server/unbound.nix
# Unbound — validating, recursive, caching DNS resolver.
# Uses port 5335 (the conventional Unbound-behind-AdGuard/Pi-hole port) to avoid
# conflict with AdGuard Home (port 53) and Avahi mDNS (port 5353).
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
          port = 5335;
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

    networking.firewall.allowedTCPPorts = [ 5335 ];
    networking.firewall.allowedUDPPorts = [ 5335 ];
  };
}
