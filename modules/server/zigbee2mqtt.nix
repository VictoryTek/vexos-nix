# modules/server/zigbee2mqtt.nix
# Zigbee2MQTT — bridges Zigbee devices to MQTT, no proprietary hub required.
# Default frontend port: 8088 (non-standard to avoid conflict with port 8080 services)
# Set serialPort to your Zigbee coordinator device (e.g. /dev/ttyUSB0, /dev/ttyACM0).
# MQTT broker: this module assumes an MQTT broker is running at localhost:1883.
# Pair with home-assistant or node-red for automations.
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

    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
