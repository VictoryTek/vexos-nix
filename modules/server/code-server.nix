# modules/server/code-server.nix
# code-server — VS Code in the browser, accessible from any device on the LAN.
# Deployed as a pinned container (codercom/code-server) rather than the
# nixpkgs package because the stable package lags upstream by many minors.
# Default port: 4444
#
# Upstream: https://github.com/coder/code-server
#
# homeDir (default /home/code-server — the old native service user's home)
# is bind-mounted to /home/coder, so existing settings, extensions and
# projects are reused in place. The container runs as userId:groupId, which
# must own homeDir (see userId below).
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

    homeDir = lib.mkOption {
      type = lib.types.str;
      default = "/home/code-server";
      description = ''
        Host directory bind-mounted to /home/coder — code-server's settings,
        extensions, and the default workspace. The default matches the old
        native service user's home so existing data is reused.
      '';
    };

    userId = lib.mkOption {
      type = lib.types.int;
      default = 1000;
      description = ''
        UID the container runs as. Must own homeDir; if existing data is
        owned by the old code-server system user, chown it to this UID/GID
        (or set this to that user's UID).
      '';
    };

    groupId = lib.mkOption {
      type = lib.types.int;
      default = 1000;
      description = "GID the container runs as.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open the firewall for code-server's port.";
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

    vexos.server.backup.servicePaths.code-server = [ cfg.homeDir ];

    virtualisation.docker.enable = lib.mkDefault true;
    virtualisation.oci-containers.backend = lib.mkDefault "docker";

    systemd.tmpfiles.rules = [
      "d ${cfg.homeDir} 0750 ${toString cfg.userId} ${toString cfg.groupId} -"
    ];

    virtualisation.oci-containers.containers.code-server = {
      image = "codercom/code-server:4.141.0";
      ports = [ "${toString cfg.port}:8080" ];
      user = "${toString cfg.userId}:${toString cfg.groupId}";
      environment = {
        HASHED_PASSWORD = cfg.hashedPassword;
        HOME = "/home/coder";
        TZ = config.time.timeZone;
      };
      volumes = [ "${cfg.homeDir}:/home/coder" ];
      cmd = [ "--auth=password" "--bind-addr=0.0.0.0:8080" "/home/coder" ];
    };

    networking.firewall.allowedTCPPorts = lib.optional cfg.openFirewall cfg.port;
  };
}
