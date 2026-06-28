# modules/remote-desktop-server.nix
# GNOME Remote Desktop system-daemon credential setup for server roles.
#
# Imported ONLY by configuration-server.nix.
# Desktop and htpc roles use modules/remote-desktop.nix (user daemon + GNOME Keyring).
#
# Why a separate module:
#   Server auto-login bypasses the PAM password prompt, so the GNOME Keyring is never
#   unlocked. The user-daemon grdctl rdp set-credentials call (used by remote-desktop.nix)
#   fails with "Cannot create an item in a locked collection". Additionally, the
#   password file (/etc/nixos/secrets/rdp-password) is root-owned and unreadable by the
#   user service.
#
#   The system daemon stores credentials in /var/lib/gnome-remote-desktop/ (root-owned
#   files, no keyring). A system service running as root can read the password file and
#   call grdctl --system without polkit (root bypasses polkit unconditionally).
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
      Created by 'just setup-rdp'. When present, the vexos-rdp-setup system service
      calls grdctl --system to enable RDP and set credentials at graphical.target.
      When absent, the service exits silently — no error.
    '';
  };

  config = {
    systemd.services.vexos-rdp-setup = {
      description = "Configure GNOME Remote Desktop system daemon credentials";
      wantedBy    = [ "graphical.target" ];
      after       = [ "graphical.target" "dbus.service" ];
      # polkit provides pkexec, which grdctl --system calls internally even as root
      path        = [ pkgs.gnome-remote-desktop pkgs.polkit ];
      script      = ''
        if [ ! -f ${lib.escapeShellArg cfg.passwordFile} ]; then
          exit 0
        fi
        password=$(cat ${lib.escapeShellArg cfg.passwordFile})
        # Root bypasses polkit — no interactive auth required for grdctl --system.
        # gnome-remote-desktop-configuration.service is D-Bus activated on demand.
        grdctl --system rdp enable
        grdctl --system rdp set-credentials ${lib.escapeShellArg username} "$password"
        grdctl --system rdp disable-view-only
        # Start the system daemon so it picks up credentials and listens on port 3389.
        systemctl start gnome-remote-desktop.service
      '';
      serviceConfig = {
        Type            = "oneshot";
        RemainAfterExit = true;
      };
    };
  };
}
