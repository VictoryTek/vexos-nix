# modules/server/home-assistant.nix
# Home Assistant — home automation platform.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.home-assistant;
in
{
  options.vexos.server.home-assistant = {
    enable = lib.mkEnableOption "Home Assistant automation";
  };

  config = lib.mkIf cfg.enable {
    services.home-assistant = {
      enable = true;
      openFirewall = true; # Port 8123
      extraComponents = [
        "default_config"
        "met"       # Weather
        "esphome"   # ESPHome devices
        "zha"       # Zigbee
      ];
      config = {
        homeassistant = {
          name = "Home";
          unit_system = lib.mkDefault "imperial";
          time_zone = lib.mkDefault config.time.timeZone;
        };
        http = {
          server_port = 8123;
        };
      };
    };
  };
}
