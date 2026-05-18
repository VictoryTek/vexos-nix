# modules/server/minio.nix
# MinIO — S3-compatible object storage server.
# API default port: 9000
# Console default port: 9001
# Credentials default path: /etc/nixos/secrets/minio-credentials
#   Override via vexos.server.minio.rootCredentialsFile for alternate backends.
# Create file containing:
#   MINIO_ROOT_USER=admin
#   MINIO_ROOT_PASSWORD=changeme123
#   Create with: sudo install -m 0600 -o root -g root /dev/stdin /etc/nixos/secrets/minio-credentials
#   Permissions enforced at boot by modules/secrets.nix (0700 dir, 0600 files).
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
      description = "Port for the MinIO S3 API.";
    };

    consolePort = lib.mkOption {
      type = lib.types.port;
      default = 9001;
      description = "Port for the MinIO web console.";
    };

    rootCredentialsFile = lib.mkOption {
      type = lib.types.str;
      default = "/etc/nixos/secrets/minio-credentials";
      description = ''
        Path to the MinIO root credentials environment file.
        Default keeps legacy plaintext behavior; the sops backend overrides this
        to a decrypted runtime template path.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.minio = {
      enable = true;
      listenAddress = ":${toString cfg.apiPort}";
      consoleAddress = ":${toString cfg.consolePort}";
      rootCredentialsFile = cfg.rootCredentialsFile;
    };

    networking.firewall.allowedTCPPorts = [ cfg.apiPort cfg.consolePort ];
  };
}
