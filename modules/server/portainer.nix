# modules/server/portainer.nix
# Portainer CE — container management web UI (OCI container).
# Deployed as an OCI container, backed by either Docker or Podman
# (vexos.server.portainer.backend). Only the selected backend is required —
# enabling Portainer with backend = "docker" does not require Podman, and
# vice versa.
# Default port: 9443 (HTTPS)
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.portainer;
in
{
  options.vexos.server.portainer = {
    enable = lib.mkEnableOption "Portainer Docker management UI";

    backend = lib.mkOption {
      type        = lib.types.enum [ "docker" "podman" ];
      default     = "docker";
      description = ''
        Container runtime Portainer manages and is deployed under.
        "docker" defaults vexos.server.docker.enable on and mounts the real
        Docker socket. "podman" requires vexos.server.podman.enable = true
        and mounts Podman's Docker-compat socket. Only the selected backend
        is required.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 9443;
      description = "HTTPS port for the Portainer web UI.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open the firewall for Portainer's port.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.backend != "podman" || config.vexos.server.podman.enable;
        message   = "vexos.server.portainer.enable with backend = \"podman\" requires vexos.server.podman.enable = true. Enable Podman first, or set vexos.server.portainer.backend = \"docker\".";
      }
      {
        assertion = cfg.backend != "docker" || !config.vexos.server.podman.enable;
        message   = "vexos.server.portainer.enable with backend = \"docker\" (the default) conflicts with vexos.server.podman.enable = true on the same host — Podman forces virtualisation.docker.enable off and takes over virtualisation.oci-containers.backend, which would break Portainer's Docker socket mount. Set vexos.server.portainer.backend = \"podman\" instead.";
      }
    ];

    virtualisation.docker.enable = lib.mkIf (cfg.backend == "docker") (lib.mkDefault true);
    virtualisation.oci-containers.backend = lib.mkIf (cfg.backend == "docker") (lib.mkDefault "docker");

    virtualisation.oci-containers.containers.portainer = {
      image = "portainer/portainer-ce:2.43.0";
      ports = [ "${toString cfg.port}:9443" ];
      volumes = [
        (if cfg.backend == "docker"
         then "/var/run/docker.sock:/var/run/docker.sock:ro"
         else "/run/podman/podman.sock:/var/run/docker.sock:ro")
        "portainer-data:/data"
      ];
    };

    networking.firewall.allowedTCPPorts = lib.optional cfg.openFirewall cfg.port;
  };
}
