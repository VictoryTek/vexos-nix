# modules/server/plex.nix
# Plex Media Server — proprietary streaming media server.
# Plex Pass hardware transcoding: set plexPass = true to expose GPU devices.
# accelerationDevices defaults to ["*"] (all devices) which is sufficient for most setups.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.plex;
in
{
  options.vexos.server.plex = {
    enable = lib.mkEnableOption "Plex Media Server";

    plexPass = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Enable Plex Pass hardware transcoding support.
        Passes all GPU/hardware acceleration devices into the Plex service.
        Requires an active Plex Pass subscription — enable it in the Plex web UI
        under Settings → Transcoder → Use hardware acceleration when available.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.plex = {
      enable = true;
      openFirewall = true;
      # When plexPass is enabled, expose all acceleration devices (GPUs, codecs, etc.)
      # Default is already ["*"] in nixpkgs, but we set it explicitly for clarity.
      accelerationDevices = lib.mkIf cfg.plexPass [ "*" ];
    };

    users.users.nimda.extraGroups = [ "plex" ];
  };
}
