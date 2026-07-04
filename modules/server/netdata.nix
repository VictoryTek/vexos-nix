# modules/server/netdata.nix
# Netdata — real-time system performance and health monitoring.
# Default port: 19999
# ⚠ No authentication of its own — anyone who can reach the port can view full
#   system metrics. Set openFirewall = false to restrict access to localhost/VPN only.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.netdata;
in
{
  options.vexos.server.netdata = {
    enable = lib.mkEnableOption "Netdata real-time system monitoring";

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Open the firewall for Netdata's port. Defaults to true — Netdata is
        intended to be viewable from other devices on the LAN. It has no
        authentication of its own; set to false to restrict access to
        localhost/VPN only.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.netdata = {
      enable = true;
    };

    networking.firewall.allowedTCPPorts = lib.optional cfg.openFirewall 19999;
  };
}
