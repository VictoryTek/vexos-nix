# modules/server/zigbee2mqtt.nix
# Zigbee2MQTT — bridges Zigbee devices to MQTT, no proprietary hub required.
# Default frontend port: 8088 (non-standard to avoid conflict with port 8080 services)
# Set serialPort to your Zigbee coordinator device (e.g. /dev/ttyUSB0, /dev/ttyACM0).
# MQTT broker: Mosquitto is started automatically on 127.0.0.1:1883 (loopback-only, not firewalled).
# Pair with home-assistant or node-red for automations.
# ⚠ The web frontend has no authentication of its own — anyone who can reach the
#   port can control paired Zigbee devices. Set openFirewall = false to restrict
#   access to localhost/VPN only.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.zigbee2mqtt;
in
{
  options.vexos.server.zigbee2mqtt = {
    enable = lib.mkEnableOption "Zigbee2MQTT Zigbee bridge";

    serialPort = lib.mkOption {
      type = lib.types.str;
      default = "/dev/ttyUSB0";
      description = "Path to the Zigbee coordinator serial device (e.g. /dev/ttyUSB0, /dev/ttyACM0).";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8088;
      description = "Port for the Zigbee2MQTT web frontend.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Open the firewall for the Zigbee2MQTT web frontend. Defaults to true —
        the frontend is intended to be reachable from other devices on the
        LAN. It has no authentication of its own; set to false to restrict
        access to localhost/VPN only.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.zigbee2mqtt = {
      enable = true;
      settings = {
        homeassistant = false;
        permit_join = false;
        serial.port = cfg.serialPort;
        frontend = {
          enabled = true;
          port = cfg.port;
          host = "0.0.0.0";
        };
        mqtt.server = "mqtt://localhost:1883";
        advanced.log_level = "info";
      };
    };

    services.mosquitto = {
      enable = true;
      listeners = [
        {
          address = "127.0.0.1";
          port = 1883;
          acl = [ "pattern readwrite #" ];
          omitPasswordAuth = true;
          settings.allow_anonymous = true;
        }
      ];
    };

    systemd.services.zigbee2mqtt = {
      after = [ "mosquitto.service" ];
      requires = [ "mosquitto.service" ];
    };

    networking.firewall.allowedTCPPorts = lib.optional cfg.openFirewall cfg.port;
  };
}
