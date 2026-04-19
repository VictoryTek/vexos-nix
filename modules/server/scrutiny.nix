# modules/server/scrutiny.nix
# Scrutiny — hard drive health monitoring via S.M.A.R.T. data (web UI + collector).
# Default web port: 8080 — adjust if it conflicts with other services.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.scrutiny;
in
{
  options.vexos.server.scrutiny = {
    enable = lib.mkEnableOption "Scrutiny disk health monitoring";
  };

  config = lib.mkIf cfg.enable {
    services.scrutiny = {
      enable = true;
      openFirewall = true; # Default port: 8080
      collector.enable = true;
    };
  };
}
