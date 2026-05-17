# modules/server/adguard.nix
# AdGuard Home — network-wide DNS ad blocking.
#
# DNS exposure:
#   By default the DNS listener binds to loopback only (127.0.0.1 / ::1) and
#   the DNS firewall ports are NOT opened. This prevents an open recursive
#   resolver from being reachable on the WAN, which could be enrolled in DNS
#   amplification attacks on dual-homed hosts.
#
#   To serve DNS on the LAN, set:
#     vexos.server.adguard.dnsBindHosts = [ "0.0.0.0" ];   # or specific LAN IP
#     vexos.server.adguard.openDnsFirewall = true;
#
#   Restrict further with per-interface rules in your host config:
#     networking.firewall.interfaces."eth0".allowedUDPPorts = [ 53 ];
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.adguard;
in
{
  options.vexos.server.adguard = {
    enable = lib.mkEnableOption "AdGuard Home DNS ad blocker";

    port = lib.mkOption {
      type = lib.types.port;
      default = 3080;
      description = "Port for the AdGuard Home web interface.";
    };

    dnsBindHosts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "127.0.0.1" "::1" ];
      description = ''
        Addresses AdGuard Home will bind its DNS listener to.
        Default is loopback only. Set to [ "0.0.0.0" ] (and enable
        openDnsFirewall) to serve DNS on the LAN.
      '';
    };

    openDnsFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Open TCP/UDP port 53 in the firewall. Off by default — enable
        only on hosts that are the intended LAN DNS resolver, and
        consider scoping to a specific interface in your host config.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.adguardhome = {
      enable = true;
      openFirewall = true;
      settings = {
        http = {
          address = "0.0.0.0:${toString cfg.port}";
        };
        dns = {
          bind_hosts = cfg.dnsBindHosts;
          port = 53;
        };
      };
    };

    networking.firewall.allowedTCPPorts = lib.optional cfg.openDnsFirewall 53;
    networking.firewall.allowedUDPPorts = lib.optional cfg.openDnsFirewall 53;
  };
}
