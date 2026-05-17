# modules/server/syncthing.nix
# Syncthing — continuous peer-to-peer file synchronization.
#
# GUI security:
#   The Syncthing web GUI is bound to 127.0.0.1:8384 by default and the
#   firewall port is NOT opened. Access it via SSH port-forwarding:
#     ssh -L 8384:localhost:8384 <host>
#   or place it behind a reverse proxy with authentication.
#
#   To expose the GUI on the LAN directly (e.g. for a trusted home network):
#     vexos.server.syncthing.guiAddress = "0.0.0.0:8384";
#     vexos.server.syncthing.openGuiFirewall = true;
#   ⚠ Syncthing's GUI has no authentication on a fresh install. Set a GUI
#     password in the web interface before enabling LAN exposure.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.syncthing;
in
{
  options.vexos.server.syncthing = {
    enable = lib.mkEnableOption "Syncthing file sync";

    guiAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1:8384";
      description = ''
        Address the Syncthing GUI listens on. Default is loopback-only;
        access via SSH tunnel or a reverse proxy with auth. Set to
        "0.0.0.0:8384" (with openGuiFirewall = true) for direct LAN access —
        ensure a GUI password is configured first.
      '';
    };

    openGuiFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Open TCP 8384 in the firewall for the Syncthing GUI.
        Disabled by default — enable only after setting a GUI password.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.syncthing = {
      enable = true;
      user = config.vexos.user.name;
      dataDir = "/home/${config.vexos.user.name}";
      configDir = "/home/${config.vexos.user.name}/.config/syncthing";
      openDefaultPorts = true;
      guiAddress = cfg.guiAddress;
    };

    networking.firewall.allowedTCPPorts =
      lib.optional cfg.openGuiFirewall 8384;
  };
}

