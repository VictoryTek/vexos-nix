# modules/server/vexboard.nix
# VexBoard — self-hosted server dashboard for VexOS Server.
# Opt-in: enabled automatically by `just enable <service>` when the first service is enabled.
# Enable/disable in /etc/nixos/server-services.nix:
#   vexos.server.vexboard.enable = true;   # or false to suppress
#
# Web UI:  http://<server-ip>:7280
# Service: vexboard.service
{ config, lib, ... }:
let
  cfg = config.vexos.server.vexboard;
in
{
  options.vexos.server.vexboard = {
    enable = lib.mkEnableOption "VexBoard server dashboard";

    port = lib.mkOption {
      type = lib.types.port;
      default = 7280;
      description = "Port VexBoard listens on.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open the firewall for VexBoard's port.";
    };

    secretFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to a file containing VEXBOARD_AUTH__SECRET. Generate with:
          openssl rand -base64 48
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.vexboard = {
      enable = true;
      port = cfg.port;
      openFirewall = cfg.openFirewall;
      secretFile = cfg.secretFile;
    };
  };
}
