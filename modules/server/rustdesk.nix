# modules/server/rustdesk.nix
# RustDesk Server — self-hosted relay and signal server for RustDesk remote desktop.
# Ports: 21115 (signal TCP), 21116 (relay TCP/UDP), 21117 (relay TCP), 21118/21119 (WebSocket)
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.rustdesk;
in
{
  options.vexos.server.rustdesk = {
    enable = lib.mkEnableOption "RustDesk relay/signal server";

    relayIP = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Public IP address of this server (required for relay). Set to your server's public IP.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.rustdesk-server = {
      enable = true;
      openFirewall = true;
    } // lib.optionalAttrs (cfg.relayIP != "") {
      relayIP = cfg.relayIP;
    };
  };
}
