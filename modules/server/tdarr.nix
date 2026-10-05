# modules/server/tdarr.nix
# Tdarr — distributed transcode automation (FFmpeg/HandBrake). Uses the native
# nixpkgs services.tdarr module (unfree; allowed by modules/nix.nix). Runs the
# server plus one local worker node by default, so the host transcodes out of
# the box; set node.enable = false to run a server-only coordinator and attach
# remote nodes elsewhere.
#
# Web UI: http://<server-ip>:8265. Node-to-server API: 8266.
#
# Point libraries at your media from the Tdarr web UI. Tdarr rewrites files in
# place by default — test on a copy of a library first.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.tdarr;
  storageMounts = import ../lib/storage-mount-ordering.nix { inherit lib; };
in
{
  options.vexos.server.tdarr = {
    enable = lib.mkEnableOption "Tdarr transcode automation server";

    node.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Also run a local Tdarr worker node on this host.";
    };

    mediaMounts = storageMounts.mediaMountsOption;

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open the firewall for the Tdarr web UI and server API ports.";
    };
  };

  config = lib.mkIf cfg.enable {
    vexos.server.backup.servicePaths.tdarr = [ config.services.tdarr.dataDir ];

    services.tdarr = {
      server = {
        enable = true;
        openFirewall = cfg.openFirewall;
      };
      nodes.local.enable = cfg.node.enable;
    };

    # The server scans libraries and the node transcodes them — order both
    # after the media storage.
    systemd.services.tdarr-server.unitConfig = storageMounts.requiresMountsFor cfg.mediaMounts;
    systemd.services.tdarr-node-local.unitConfig = storageMounts.requiresMountsFor cfg.mediaMounts;
  };
}
