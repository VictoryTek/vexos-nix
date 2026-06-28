# modules/remote-desktop.nix
# Automatic GNOME Remote Desktop (RDP) credential setup.
#
# Imported by: configuration-desktop.nix, configuration-server.nix, configuration-htpc.nix
# NOT imported by: configuration-stateless.nix (tmpfs home — GNOME Keyring state is
# ephemeral and credentials do not survive reboots without extra impermanence config)
#
# Setup: run `just setup-rdp` on the machine to write the password file.
# After the next `just switch`, RDP credentials are applied automatically on
# every GNOME session start. Username is derived from vexos.user.name.
{ config, lib, pkgs, ... }:
let
  cfg      = config.vexos.remoteDesktop;
  username = config.vexos.user.name;
in
{
  options.vexos.remoteDesktop.passwordFile = lib.mkOption {
    type        = lib.types.str;
    default     = "/etc/nixos/secrets/rdp-password";
    description = ''
      Path to a file containing the plaintext RDP password (no trailing newline).
      Created by 'just setup-rdp'. When present, a systemd user service calls
      grdctl to enable RDP and set credentials on every GNOME session start.
      When absent, the service exits silently — no error.
    '';
  };

  config = {
    systemd.user.services.vexos-rdp-setup = {
      description = "Configure GNOME Remote Desktop credentials";
      wantedBy    = [ "graphical-session.target" ];
      # wants ensures the user gnome-remote-desktop daemon is running before
      # grdctl tries to configure it via D-Bus. Without this, the daemon may
      # not yet be active when the script runs, making the credential calls no-ops.
      wants       = [ "gnome-remote-desktop.service" ];
      after       = [ "graphical-session.target" "gnome-remote-desktop.service" ];
      partOf      = [ "graphical-session.target" ];
      path        = [ pkgs.gnome-remote-desktop ];
      script      = ''
        if [ ! -f ${lib.escapeShellArg cfg.passwordFile} ]; then
          exit 0
        fi
        password=$(cat ${lib.escapeShellArg cfg.passwordFile})
        grdctl rdp enable
        grdctl rdp set-credentials ${lib.escapeShellArg username} "$password"
      '';
      serviceConfig = {
        Type            = "oneshot";
        RemainAfterExit = true;
      };
    };
  };
}
