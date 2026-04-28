# modules/server/minio.nix
# MinIO — S3-compatible object storage server.
# API default port: 9000  ⚠ conflicts with Mealie — set apiPort if both are enabled.
# Console default port: 9001
# Credentials: create /etc/nixos/secrets/minio-credentials containing:
#   MINIO_ROOT_USER=admin
#   MINIO_ROOT_PASSWORD=changeme123
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.minio;
in
{
  options.vexos.server.minio = {
    enable = lib.mkEnableOption "MinIO S3-compatible object storage";

    apiPort = lib.mkOption {
      type = lib.types.port;
      default = 9000;
      description = "Port for the MinIO S3 API. ⚠ Conflicts with Mealie on port 9000.";
    };

    consolePort = lib.mkOption {
      type = lib.types.port;
      default = 9001;
      description = "Port for the MinIO web console.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.minio = {
      enable = true;
      listenAddress = ":${toString cfg.apiPort}";
      consoleAddress = ":${toString cfg.consolePort}";
      rootCredentialsFile = "/etc/nixos/secrets/minio-credentials";
    };

    networking.firewall.allowedTCPPorts = [ cfg.apiPort cfg.consolePort ];
  };
}
