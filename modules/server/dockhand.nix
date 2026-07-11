# modules/server/dockhand.nix
# Dockhand — container management UI that speaks the Docker API.
# Deployed as an OCI container, backed by either Docker or Podman
# (vexos.server.dockhand.backend). Only the selected backend is required —
# enabling Dockhand with backend = "docker" does not require Podman, and
# vice versa.
#
# Prerequisites:
#   backend = "docker" (default): vexos.server.docker.enable is defaulted on
#                                 automatically, same as arcane.nix/portainer.nix.
#   backend = "podman":           vexos.server.podman.enable = true (enforced
#                                 by assertion below).
#
# Default access:  http://<host-ip>:8073
# On first launch: authentication is DISABLED — go to Settings > Authentication
#                  immediately after first access to secure the instance.
#
# Data is stored at vexos.server.dockhand.dataDir (default /var/lib/dockhand).
# Using matching paths (host path == container path) so compose stacks with
# relative volume bind mounts work correctly.
{ config, lib, ... }:
let
  cfg = config.vexos.server.dockhand;
in
{
  options.vexos.server.dockhand = {
    enable = lib.mkEnableOption "Dockhand container management UI";

    backend = lib.mkOption {
      type        = lib.types.enum [ "docker" "podman" ];
      default     = "docker";
      description = ''
        Container runtime Dockhand manages and is deployed under.
        "docker" defaults vexos.server.docker.enable on and mounts the real
        Docker socket. "podman" requires vexos.server.podman.enable = true
        and mounts Podman's Docker-compat socket. Only the selected backend
        is required.
      '';
    };

    port = lib.mkOption {
      type        = lib.types.port;
      default     = 8073; # 3000 is Forgejo's default port; shifted to 8073 to avoid conflict
      description = "Host port on which Dockhand listens.";
    };

    dataDir = lib.mkOption {
      type        = lib.types.str;
      default     = "/var/lib/dockhand";
      description = ''
        Host directory for Dockhand persistent data (SQLite database, compose
        stack definitions, Git repository clones).
        Uses matching paths: this directory is mounted at the same absolute
        path inside the container and DATA_DIR is set accordingly.
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open the firewall for Dockhand's port.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.backend != "podman" || config.vexos.server.podman.enable;
        message   = "vexos.server.dockhand.enable with backend = \"podman\" requires vexos.server.podman.enable = true. Enable Podman first, or set vexos.server.dockhand.backend = \"docker\".";
      }
      {
        assertion = cfg.backend != "docker" || !config.vexos.server.podman.enable;
        message   = "vexos.server.dockhand.enable with backend = \"docker\" (the default) conflicts with vexos.server.podman.enable = true on the same host — Podman forces virtualisation.docker.enable off and takes over virtualisation.oci-containers.backend, which would break Dockhand's Docker socket mount. Set vexos.server.dockhand.backend = \"podman\" instead.";
      }
    ];

    # Ensure the data directory exists with correct permissions before the
    # container service starts.
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0700 root root -"
    ];

    virtualisation.docker.enable = lib.mkIf (cfg.backend == "docker") (lib.mkDefault true);
    virtualisation.oci-containers.backend = lib.mkIf (cfg.backend == "docker") (lib.mkDefault "docker");

    virtualisation.oci-containers.containers.dockhand = {
      image     = "ghcr.io/finsys/dockhand:v1.0.36";
      autoStart = true;

      # Expose Dockhand on the configured host port.
      ports = [ "0.0.0.0:${toString cfg.port}:3000" ];

      # Mount the backend's Docker-API socket and the persistent data
      # directory using matching paths.
      volumes = [
        (if cfg.backend == "docker"
         then "/var/run/docker.sock:/var/run/docker.sock"
         else "/run/podman/podman.sock:/var/run/docker.sock:ro")  # Podman native socket (read-only)
        "${cfg.dataDir}:${cfg.dataDir}"          # Matching-path persistent data
      ];

      environment = {
        DATA_DIR = cfg.dataDir;
      };

      # Run as root to avoid Docker group GID-matching complexity.
      # Acceptable for home-lab environments per Dockhand official docs.
      # See: https://dockhand.pro/manual/#docker-socket-permissions
      user = "0:0";
    };

    # Open the firewall for Dockhand's web UI.
    networking.firewall.allowedTCPPorts = lib.optional cfg.openFirewall cfg.port;
  };
}
