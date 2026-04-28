# modules/server/code-server.nix
# code-server — VS Code in the browser, accessible from any device on the LAN.
# Default port: 4444
# Password: if hashedPassword is set, auth is enabled. Otherwise auth=none.
#   Generate an argon2 hash: echo -n 'yourpassword' | nix run nixpkgs#libargon2 -- "$(head -c 20 /dev/random | base64)" -e
#   Then set the resulting hash string as hashedPassword in your host config.
# ⚠ Bind behind a TLS reverse proxy before exposing outside the LAN.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.code-server;
in
{
  options.vexos.server.code-server = {
    enable = lib.mkEnableOption "code-server VS Code in the browser";

    port = lib.mkOption {
      type = lib.types.port;
      default = 4444;
      description = "Port for the code-server web interface.";
    };

    hashedPassword = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = ''
        Argon2-hashed password for code-server authentication.
        If empty, authentication is disabled (suitable for trusted LAN only).
        Generate with: echo -n 'yourpassword' | nix run nixpkgs#libargon2 -- "$(head -c 20 /dev/random | base64)" -e
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.code-server = {
      enable = true;
      host = "0.0.0.0";
      port = cfg.port;
      auth = if cfg.hashedPassword != "" then "password" else "none";
      hashedPassword = cfg.hashedPassword;
    };

    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
