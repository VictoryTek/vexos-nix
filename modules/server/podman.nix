# modules/server/podman.nix
# Podman container runtime with Docker API compatibility.
# Enables the Docker-compat socket at /run/docker.sock so that Docker-API
# clients (e.g. Dockhand) can communicate with Podman transparently.
# Sets virtualisation.oci-containers.backend = "podman" so that all OCI
# container services on this system use Podman as the runtime.
{ config, lib, ... }:
let
  cfg = config.vexos.server.podman;
in
{
  options.vexos.server.podman = {
    enable = lib.mkEnableOption "Podman container runtime with Docker API compatibility";
  };

  config = lib.mkIf cfg.enable {
    virtualisation.podman = {
      enable       = true;
      dockerCompat = true;  # Creates /run/docker.sock (Docker-compat API socket)
      defaultNetwork.settings.dns_enabled = true;  # Inter-container DNS resolution
      autoPrune = {
        enable = true;
        dates  = "weekly";  # Remove unused images/containers weekly
      };
    };

    # Use Podman as the backend for all declarative OCI container services
    # (virtualisation.oci-containers.containers.*).
    virtualisation.oci-containers.backend = "podman";

    # Several docker-backed service modules set virtualisation.docker.enable =
    # lib.mkDefault true so they work standalone. Podman's dockerCompat above
    # already provides the same /run/docker.sock those modules need, and
    # nixpkgs asserts against dockerCompat + real docker running together —
    # force real docker off so podman + those services can coexist.
    virtualisation.docker.enable = lib.mkForce false;

    assertions = [
      {
        assertion = !(config.vexos.server.docker.enable or false);
        message   = "vexos.server.podman and vexos.server.docker should not both be enabled on the same host. Choose one container runtime.";
      }
    ];
  };
}
