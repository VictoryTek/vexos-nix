# modules/server/scrutiny.nix
# Scrutiny — hard drive health monitoring via S.M.A.R.T. data (web UI + collector).
# Default web port: 8078
#
# smartd:
#   Enabled alongside Scrutiny by default (enableSmartd = true). smartd provides
#   independent journald-visible SMART health alerts (temperature thresholds,
#   reallocated sector counts) without requiring the Scrutiny web UI to be running.
#   Disable via vexos.server.scrutiny.enableSmartd = false if smartd is managed
#   separately or the host is a VM where SMART is not available.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.scrutiny;
in
{
  options.vexos.server.scrutiny = {
    enable = lib.mkEnableOption "Scrutiny disk health monitoring";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8078;
      description = "Port for the Scrutiny web interface.";
    };

    enableSmartd = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Enable services.smartd alongside Scrutiny for journald-visible SMART health
        alerts independent of the Scrutiny web UI. Set to false on VMs or hosts
        where SMART is unavailable or managed by a separate module.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.scrutiny = {
      enable = true;
      openFirewall = true;
      settings.web.listen.port = cfg.port;
      collector.enable = true;
    };

    services.smartd.enable = lib.mkDefault cfg.enableSmartd;
  };
}