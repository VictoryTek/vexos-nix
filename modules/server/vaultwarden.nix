# modules/server/vaultwarden.nix
# Vaultwarden — lightweight Bitwarden-compatible password manager server.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.vaultwarden;
in
{
  options.vexos.server.vaultwarden = {
    enable = lib.mkEnableOption "Vaultwarden password manager";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8222;
      description = "Port for the Vaultwarden web vault.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.vaultwarden = {
      enable = true;
      config = {
        ROCKET_PORT = cfg.port;
        SIGNUPS_ALLOWED = false;
      };
    };

    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
