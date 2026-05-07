# modules/server/attic.nix
# Attic — modern, purpose-built NixOS binary cache server.
# Default port: 8400 (avoids conflicts with SABnzbd/scrutiny on 8080).
# Requires: /etc/nixos/secrets/attic-credentials containing:
#   ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64=<secret>
# Generate secret with: openssl genrsa -traditional 4096 | base64 -w0
# After enabling, use `attic login` on clients pointing to http://<host>:8400
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.attic;
in
{
  options.vexos.server.attic = {
    enable = lib.mkEnableOption "Attic Nix binary cache server";

    port = lib.mkOption {
      type    = lib.types.port;
      default = 8400;
      description = "Port for the Attic HTTP listener.";
    };

    dataDir = lib.mkOption {
      type    = lib.types.path;
      default = "/var/lib/atticd";
      description = "Directory for the SQLite database and local cache storage.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.atticd = {
      enable = true;
      environmentFile = "/etc/nixos/secrets/attic-credentials";
      settings = {
        listen = "[::]:${toString cfg.port}";
        database.url = "sqlite://${cfg.dataDir}/db.sqlite?mode=rwc";
        storage = {
          type = "local";
          path = "${cfg.dataDir}/storage";
        };
        chunking = {
          nar-size-threshold = 65536;  # 64 KiB — chunk NARs larger than this
          min-size           = 16384;  # 16 KiB
          avg-size           = 65536;  # 64 KiB
          max-size           = 262144; # 256 KiB
        };
      };
    };

    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
