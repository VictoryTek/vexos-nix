# modules/server/stirling-pdf.nix
# Stirling PDF — full-featured PDF manipulation tools (OCI container).
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.stirling-pdf;
in
{
  options.vexos.server.stirling-pdf = {
    enable = lib.mkEnableOption "Stirling PDF tools";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8077;
      description = "Port for the Stirling PDF web interface.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open the firewall for Stirling PDF's port.";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.docker.enable = lib.mkDefault true;
    virtualisation.oci-containers.backend = lib.mkDefault "docker";

    virtualisation.oci-containers.containers.stirling-pdf = {
      image = "frooodle/s-pdf:2.14.0";
      ports = [ "${toString cfg.port}:8080" ];
      volumes = [
        "stirling-pdf-data:/usr/share/tessdata"
        "stirling-pdf-config:/configs"
      ];
    };

    networking.firewall.allowedTCPPorts = lib.optional cfg.openFirewall cfg.port;
  };
}
