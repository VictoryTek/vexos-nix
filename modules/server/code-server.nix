# modules/server/code-server.nix
# code-server — VS Code in the browser, accessible from any device on the LAN.
# Default port: 4444
# Password: hashedPassword is required — auth=none is not permitted.
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
        Must be set — code-server with auth=none on 0.0.0.0 is equivalent to
        a passwordless remote shell accessible to anyone on the network.
        Generate with: echo -n 'yourpassword' | nix run nixpkgs#libargon2 -- "$(head -c 20 /dev/random | base64)" -e
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.hashedPassword != "";
        message = ''
          vexos.server.code-server.hashedPassword must be set.
          code-server with auth=none on 0.0.0.0 is a passwordless remote shell.
          Generate a hash with:
            echo -n 'yourpassword' | nix run nixpkgs#libargon2 -- "$(head -c 20 /dev/random | base64)" -e
        '';
      }
    ];

    services.code-server = {
      enable = true;
      host = "0.0.0.0";
      port = cfg.port;
      auth = "password";
      hashedPassword = cfg.hashedPassword;
    };

    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
