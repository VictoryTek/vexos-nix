# modules/server/matrix-conduit.nix
# Conduit — simple, fast Matrix homeserver written in Rust.
# Default HTTP port: 6167
# For federation, set serverName to your public domain and place a reverse proxy
# in front at /_matrix/ and /.well-known/matrix/ paths.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.matrix-conduit;
in
{
  options.vexos.server.matrix-conduit = {
    enable = lib.mkEnableOption "Conduit Matrix homeserver";

    serverName = lib.mkOption {
      type = lib.types.str;
      default = "localhost";
      description = ''
        Matrix server name (your domain, e.g. example.com).
        Appears in Matrix IDs: @user:example.com.
        Set to your actual domain for federation; use "localhost" for local-only.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 6167;
      description = "Port for the Conduit HTTP listener.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.matrix-conduit = {
      enable = true;
      settings.global = {
        server_name = cfg.serverName;
        port = cfg.port;
        address = "0.0.0.0";
        database_backend = "rocksdb";
        allow_registration = false;
        allow_federation = cfg.serverName != "localhost";
      };
    };

    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
