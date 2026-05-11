# modules/server/cockpit.nix
# Cockpit — web-based Linux server management UI, plus optional
# 45Drives plugin sub-options.
#
# Plugin discovery: Cockpit scans XDG_DATA_DIRS for share/cockpit/<name>/
# manifest.json. NixOS exposes environment.systemPackages contents
# under /run/current-system/sw/share, which is on the system XDG_DATA_DIRS,
# so adding pkgs.vexos.cockpit-navigator to systemPackages is sufficient
# — no /etc symlink, no tmpfiles. See:
#   .github/docs/subagent_docs/nas_phase_a_cockpit_navigator_spec.md
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.cockpit;
in
{
  options.vexos.server.cockpit = {
    enable = lib.mkEnableOption "Cockpit web management console";

    port = lib.mkOption {
      type = lib.types.port;
      default = 9090;
      description = "Port for the Cockpit web interface.";
    };

    navigator.enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable;
      description = ''
        Install the 45Drives cockpit-navigator file-browser plugin.
        Defaults to the value of vexos.server.cockpit.enable so that
        enabling Cockpit also installs Navigator (the simplest plugin)
        — set to false to opt out, or to true on its own to stage the
        package without enabling Cockpit (no effect at runtime).
      '';
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      services.cockpit = {
        enable = true;
        port = cfg.port;
        openFirewall = true;
      };
    })

    (lib.mkIf (cfg.enable && cfg.navigator.enable) {
      environment.systemPackages = [ pkgs.vexos.cockpit-navigator ];
    })
  ];
}
