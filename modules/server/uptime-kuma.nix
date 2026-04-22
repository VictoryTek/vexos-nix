# modules/server/uptime-kuma.nix
# Uptime Kuma — self-hosted monitoring and status page (OCI container).
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.uptime-kuma;
in
{
  options.vexos.server.uptime-kuma = {
    enable = lib.mkEnableOption "Uptime Kuma monitoring";

    port = lib.mkOption {
      type = lib.types.port;
      default = 3001;
      description = "Port for the Uptime Kuma web interface.";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.docker.enable = lib.mkDefault true;
    virtualisation.oci-containers.backend = "docker";

    virtualisation.oci-containers.containers.uptime-kuma = {
      image = "louislam/uptime-kuma:1";
      ports = [ "${toString cfg.port}:3001" ];
      volumes = [ "uptime-kuma-data:/app/data" ];
    };

    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
