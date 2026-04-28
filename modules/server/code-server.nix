# modules/server/code-server.nix
# code-server — VS Code in the browser, accessible from any device on the LAN.
# Default port: 4444
# Password: if hashedPasswordFile is set, auth is enabled. Otherwise auth=none.
#   Generate a bcrypt hash: nix shell nixpkgs#apacheHttpd -c htpasswd -nbBC 10 "" password | cut -d: -f2
#   Then write the hash (single line) to /etc/nixos/secrets/code-server-password
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

    hashedPasswordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to a file containing a bcrypt-hashed password for code-server authentication.
        If null, authentication is disabled (suitable for trusted LAN only).
        Generate with: nix shell nixpkgs#apacheHttpd -c htpasswd -nbBC 10 "" yourpassword | cut -d: -f2
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.code-server = {
      enable = true;
      host = "0.0.0.0";
      port = cfg.port;
      auth = if cfg.hashedPasswordFile != null then "password" else "none";
      hashedPasswordFile = cfg.hashedPasswordFile;
    };

    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
