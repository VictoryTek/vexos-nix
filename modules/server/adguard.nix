# modules/server/adguard.nix
# AdGuard Home — network-wide DNS ad blocking.
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
          bind_hosts = [ "0.0.0.0" ];
          port = 53;
        };
      };
    };

    # DNS port
    networking.firewall.allowedTCPPorts = [ 53 cfg.port ];
    networking.firewall.allowedUDPPorts = [ 53 ];
  };
}
