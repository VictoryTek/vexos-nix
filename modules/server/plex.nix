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

    users.users.${config.vexos.user.name}.extraGroups = [ "plex" ];

    # Without Plex Pass, hardware transcoding is unused. The NixOS plex module
    # unconditionally adds /run/opengl-driver/lib to the service LD_LIBRARY_PATH,
    # but the system libva there references __isoc23_sscanf (glibc >= 2.38) which
    # Plex's bundled libc does not provide, causing plex.service to exit 127.
    # Clearing LD_LIBRARY_PATH when hardware transcoding is off prevents Plex
    # from loading the incompatible system VA-API libraries.
    #
    # TODO(2026-11): Remove this workaround once the upstream nixpkgs Plex module
    # no longer unconditionally injects opengl-driver into LD_LIBRARY_PATH.
    # Re-checked 2026-07: still present in nixos/modules/services/misc/plex.nix
    # (environment.LD_LIBRARY_PATH = "/run/opengl-driver/lib"; unconditional, no
    # lib.mkIf gating). Check that file directly, not a GitHub issue number —
    # the previously-linked nixpkgs issue turned out to be unrelated/mistracked.
    # Verify removal: check the pinned nixpkgs' plex.nix module source directly;
    # do NOT rely solely on evaluating this repo's own LD_LIBRARY_PATH result,
    # since our own mkForce below produces "" regardless of upstream behavior.
    systemd.services.plex.environment.LD_LIBRARY_PATH =
      lib.mkIf (!cfg.plexPass) (lib.mkForce "");
  };
}
