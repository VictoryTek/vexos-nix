# modules/server/seerr.nix
# Seerr — open-source media request and discovery manager for Jellyfin, Plex, and Emby.
# Successor to Jellyseerr/Overseerr. Package sourced from nixpkgs-unstable.
# Note: Seerr, Jellyseerr, and Overseerr all default to port 5055 — enable only one.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.seerr;
in
{
  options.vexos.server.seerr = {
    enable = lib.mkEnableOption "Seerr media request manager";

    port = lib.mkOption {
      type = lib.types.port;
      default = 5055;
      description = "Port Seerr listens on.";
    };

    configDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/seerr/config";
      description = "Directory for Seerr configuration and persistent state.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open the firewall for the Seerr web interface.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.seerr = {
      description = "Seerr, a media request manager for Jellyfin, Plex, and Emby";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      environment = {
        PORT = toString cfg.port;
        CONFIG_DIRECTORY = cfg.configDir;
      };
      serviceConfig = {
        Type = "exec";
        StateDirectory = "seerr";
        DynamicUser = true;
        ExecStart = lib.getExe pkgs.unstable.seerr;
        Restart = "on-failure";
        ProtectHome = true;
        ProtectSystem = "strict";
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectHostname = true;
        ProtectClock = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        NoNewPrivileges = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        RemoveIPC = true;
        PrivateMounts = true;
      };
    };

    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [ cfg.port ];
    };
  };
}
