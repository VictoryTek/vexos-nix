# modules/server/arcane.nix
# Arcane — container management UI (OCI container). Deployed as an OCI
# container, backed by either Docker or Podman (vexos.server.arcane.backend).
# Only the selected backend is required — enabling Arcane with backend =
# "docker" does not require Podman, and vice versa.
# Grants Arcane control of the host's container runtime via the mounted
# socket — equivalent access level to Portainer; treat as root-equivalent
# exposure.
#
# Default access: http://<host-ip>:3552
#
# Required configuration:
#   vexos.server.arcane.appUrl          = "https://arcane.example.com";
#   vexos.server.arcane.environmentFile = "/etc/nixos/secrets/arcane-env";
#
#   The environment file must be a systemd EnvironmentFile (KEY=VALUE lines)
#   containing ENCRYPTION_KEY and JWT_SECRET, e.g.:
#     echo "ENCRYPTION_KEY=$(openssl rand -hex 32)"  > /etc/nixos/secrets/arcane-env
#     echo "JWT_SECRET=$(openssl rand -hex 32)"     >> /etc/nixos/secrets/arcane-env
#     chmod 0600 /etc/nixos/secrets/arcane-env
#   Without these, Arcane cannot encrypt stored secrets or sign auth tokens.
{ config, lib, ... }:
let
  cfg = config.vexos.server.arcane;
in
{
  options.vexos.server.arcane = {
    enable = lib.mkEnableOption "Arcane Docker management UI";

    backend = lib.mkOption {
      type        = lib.types.enum [ "docker" "podman" ];
      default     = "docker";
      description = ''
        Container runtime Arcane manages and is deployed under.
        "docker" defaults vexos.server.docker.enable on and mounts the real
        Docker socket. "podman" requires vexos.server.podman.enable = true
        and mounts Podman's Docker-compat socket. Only the selected backend
        is required.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 3552;
      description = "Host port on which Arcane listens.";
    };

    appUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://arcane.example.com";
      description = ''
        Public URL for this Arcane instance, e.g. "https://arcane.example.com".
        Used by Arcane to construct links and redirects. Must be set to the
        actual URL — the default placeholder is intentionally invalid.
      '';
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to a systemd EnvironmentFile (KEY=VALUE lines) providing
        ENCRYPTION_KEY and JWT_SECRET (each a 32-byte value, e.g. from
        `openssl rand -hex 32`). Required before enabling Arcane.
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open the firewall for Arcane's port.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.appUrl != "http://arcane.example.com";
        message = ''
          vexos.server.arcane.appUrl must be set to the actual public URL of
          this Arcane instance (e.g. "https://arcane.example.com").
        '';
      }
      {
        assertion = cfg.environmentFile != null;
        message = ''
          vexos.server.arcane.environmentFile must be set before enabling Arcane.
          Generate one with:
            echo "ENCRYPTION_KEY=$(openssl rand -hex 32)"  > /etc/nixos/secrets/arcane-env
            echo "JWT_SECRET=$(openssl rand -hex 32)"     >> /etc/nixos/secrets/arcane-env
            chmod 0600 /etc/nixos/secrets/arcane-env
          Then set: vexos.server.arcane.environmentFile = "/etc/nixos/secrets/arcane-env";
        '';
      }
      {
        assertion = cfg.backend != "podman" || config.vexos.server.podman.enable;
        message   = "vexos.server.arcane.enable with backend = \"podman\" requires vexos.server.podman.enable = true. Enable Podman first, or set vexos.server.arcane.backend = \"docker\".";
      }
      {
        assertion = cfg.backend != "docker" || !config.vexos.server.podman.enable;
        message   = "vexos.server.arcane.enable with backend = \"docker\" (the default) conflicts with vexos.server.podman.enable = true on the same host — Podman forces virtualisation.docker.enable off and takes over virtualisation.oci-containers.backend, which would break Arcane's Docker socket mount. Set vexos.server.arcane.backend = \"podman\" instead.";
      }
    ];

    virtualisation.docker.enable = lib.mkIf (cfg.backend == "docker") (lib.mkDefault true);
    virtualisation.oci-containers.backend = lib.mkIf (cfg.backend == "docker") (lib.mkDefault "docker");

    virtualisation.oci-containers.containers.arcane = {
      image = "ghcr.io/getarcaneapp/manager:v1.19.4";
      ports = [ "${toString cfg.port}:3552" ];
      volumes = [
        (if cfg.backend == "docker"
         then "/var/run/docker.sock:/var/run/docker.sock"
         else "/run/podman/podman.sock:/var/run/docker.sock:ro")
        "arcane-data:/app/data"
      ];
      environment = {
        APP_URL = cfg.appUrl;
        PUID = "65532";
        PGID = "65532";
      };
      environmentFiles = lib.optional (cfg.environmentFile != null) cfg.environmentFile;
    };

    networking.firewall.allowedTCPPorts = lib.optional cfg.openFirewall cfg.port;
  };
}
