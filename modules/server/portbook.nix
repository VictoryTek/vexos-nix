# modules/server/portbook.nix
# Portbook — auto-discovers HTTP servers on localhost ports and presents them
# in a web UI with live updates, a terminal list (portbook ls), and a TUI
# (portbook tui).
#
# Web UI:    http://<server-ip>:7777  (port is fixed upstream, no config flag)
# Health:    http://<server-ip>:7777/api/ports  (returns JSON, always 200)
#
# CLI tools are added to environment.systemPackages when this module is enabled:
#   portbook ls                 — one-shot grouped terminal list (great for tmux)
#   portbook tui                — interactive TUI with live updates and filter
#   portbook watch --json       — streaming JSON snapshots for scripts/agents
#   portbook explain <port>     — paste-ready diagnostic block for a single port
#
# Note: the service runs as a dedicated non-root user.  Port discovery via `ss`
# works system-wide; process-name/cwd detection is limited to processes owned
# by the portbook service user (expected, not a bug).
#
# ⚠ The package hash in pkgs/portbook/default.nix is set automatically by
#   `just enable portbook`.  See that file if you need to set it manually.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.portbook;
in
{
  options.vexos.server.portbook = {
    enable = lib.mkEnableOption "Portbook localhost port discovery dashboard";
  };

  config = lib.mkIf cfg.enable {

    users.groups.portbook = {};
    users.users.portbook = {
      isSystemUser = true;
      group        = "portbook";
      description  = "Portbook service user";
    };

    systemd.services.portbook = {
      description = "Portbook localhost port discovery dashboard";
      after       = [ "network.target" ];
      wantedBy    = [ "multi-user.target" ];

      serviceConfig = {
        Type           = "simple";
        User           = "portbook";
        Group          = "portbook";
        ExecStart      = "${pkgs.vexos.portbook}/bin/portbook serve";
        Environment    = [ "PORTBOOK_NO_OPEN=1" ];
        Restart        = "on-failure";
        RestartSec     = "5s";
        StandardOutput = "journal";
        StandardError  = "journal";
      };
    };

    # Add the binary to systemPackages so CLI subcommands (ls, tui, watch,
    # explain) are available in any user's PATH without enabling the daemon.
    environment.systemPackages = [ pkgs.vexos.portbook ];

    networking.firewall.allowedTCPPorts = [ 7777 ];
  };
}
