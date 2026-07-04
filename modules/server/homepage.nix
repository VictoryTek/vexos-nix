# modules/server/homepage.nix
# Homepage — customizable service dashboard (OCI container).
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.homepage;
in
{
  options.vexos.server.homepage = {
    enable = lib.mkEnableOption "Homepage dashboard";

    port = lib.mkOption {
      type = lib.types.port;
      default = 3010;
      description = "Port for the Homepage dashboard.";
    };

    allowedHosts = lib.mkOption {
      type = lib.types.str;
      default = "localhost:${toString cfg.port}";
      description = ''
        Comma-separated list of "host:port" combinations allowed in the
        incoming Host header. Required by Homepage v0.10+ (CSRF protection
        around Next.js Server Actions) — without it, every request is
        rejected regardless of what host/port it arrives on. There is no
        wildcard support; add every hostname/IP:port combination you'll
        actually access this dashboard through, e.g.
        "192.168.1.50:3010,homepage.local:3010".
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open the firewall for Homepage's port.";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.docker.enable = lib.mkDefault true;
    virtualisation.oci-containers.backend = lib.mkDefault "docker";

    virtualisation.oci-containers.containers.homepage = {
      image = "ghcr.io/gethomepage/homepage:v1.13.2";
      ports = [ "${toString cfg.port}:3000" ];
      volumes = [
        "homepage-config:/app/config"
        "/var/run/docker.sock:/var/run/docker.sock:ro"
      ];
      environment = {
        HOMEPAGE_ALLOWED_HOSTS = cfg.allowedHosts;
      };
    };

    networking.firewall.allowedTCPPorts = lib.optional cfg.openFirewall cfg.port;
  };
}
