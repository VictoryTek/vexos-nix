# modules/server/beszel.nix
# Beszel — lightweight server monitoring (CPU, memory, disk, network, Docker
# containers, S.M.A.R.T.) with historical data and alerts.
# Upstream: https://github.com/henrygd/beszel
#
# Two independent toggles, wrapping the native NixOS modules:
#   vexos.server.beszel        — hub (web UI + data store). Default port: 8090
#   vexos.server.beszel-agent  — agent (reports this host to a hub). Port: 45876
#
# A host can run either or both: one hub, and an agent on every server you
# want to watch (including the hub's own host).
#
# Agent setup — the agent cannot start until it knows which hub to trust:
#   1. In the hub UI: "Add System", enter this host's address and port 45876.
#   2. Copy the KEY and TOKEN values the dialog shows into the env file:
#
#        printf 'KEY=%s\nTOKEN=%s\n' "<public key>" "<token>" > /etc/nixos/secrets/beszel-agent-env
#        chmod 0600 /etc/nixos/secrets/beszel-agent-env
#
#   3. sudo systemctl restart beszel-agent
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.beszel;
  agentCfg = config.vexos.server.beszel-agent;
in
{
  options.vexos.server.beszel = {
    enable = lib.mkEnableOption "Beszel monitoring hub";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8090;
      description = "Port for the Beszel hub web interface.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Listen on all interfaces and open the firewall for the hub's port.
        Set to false to bind to 127.0.0.1 only (e.g. behind the Caddy proxy
        or a VPN).
      '';
    };
  };

  options.vexos.server.beszel-agent = {
    enable = lib.mkEnableOption "Beszel monitoring agent";

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Open the firewall for the agent's port (45876) so a hub on another
        host can connect. The agent only accepts a hub holding the key
        configured in environmentFile.
      '';
    };

    environmentFile = lib.mkOption {
      type = lib.types.path;
      default = "/etc/nixos/secrets/beszel-agent-env";
      description = ''
        systemd EnvironmentFile supplying KEY=<hub public key> and
        TOKEN=<registration token>, both shown by the hub's "Add System"
        dialog. The agent fails to start until this file exists.
      '';
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      # DynamicUser: /var/lib/beszel-hub is a symlink into /var/lib/private,
      # and restic would back up only the link, so register the real path.
      vexos.server.backup.servicePaths.beszel = [ "/var/lib/private/beszel-hub" ];

      services.beszel.hub = {
        enable = true;
        host = if cfg.openFirewall then "0.0.0.0" else "127.0.0.1";
        port = cfg.port;
      };

      networking.firewall.allowedTCPPorts = lib.optional cfg.openFirewall cfg.port;
    })

    (lib.mkIf agentCfg.enable {
      services.beszel.agent = {
        enable = true;
        openFirewall = agentCfg.openFirewall;
        environmentFile = agentCfg.environmentFile;
        smartmon.enable = true;
      };
    })
  ];
}
