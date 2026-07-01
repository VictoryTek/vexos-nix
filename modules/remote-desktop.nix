# modules/remote-desktop.nix
# Automatic GNOME Remote Desktop (RDP) credential setup.
#
# Imported by: configuration-desktop.nix, configuration-server.nix, configuration-htpc.nix
# NOT imported by: configuration-stateless.nix (tmpfs home — GNOME Keyring state is
# ephemeral and credentials do not survive reboots without extra impermanence config)
#
# Setup: run `just setup-rdp` on the machine to write the password file.
# After the next rebuild, RDP credentials are applied automatically once
# graphical.target is reached and the user session D-Bus is available.
#
# Why a system service:
#   /etc/nixos/secrets/rdp-password is root-owned (0700 parent dir enforced by
#   secrets.nix). A user service cannot read it. A system service running as root
#   reads the file and calls grdctl as the logged-in user via runuser + the user's
#   session D-Bus, so credentials land in the user daemon (no TPM required) and are
#   stored in the GNOME Keyring.
#
# Prerequisite for auto-login machines (all vexos roles use auto-login):
#   modules/gnome.nix sets security.pam.services.gdm-autologin.enableGnomeKeyring = true
#   so PAM unlocks the keyring on auto-login — but only if the keyring has an empty
#   master password. Run this once on each machine after deploying:
#     rm ~/.local/share/keyrings/login.keyring && sudo reboot
#   GNOME creates a fresh empty-password keyring that PAM can unlock without a passphrase.
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
      Created by 'just setup-rdp'. When present, a systemd system service reads it
      as root, then calls grdctl as the vexos user to enable RDP and set credentials.
      When absent, the service exits silently — no error.
    '';
  };

  config = {
    systemd.services.vexos-rdp-setup = {
      description = "Configure GNOME Remote Desktop credentials";
      wantedBy    = [ "graphical.target" ];
      after       = [ "graphical.target" "dbus.service" ];
      path        = [ pkgs.gnome-remote-desktop pkgs.coreutils pkgs.util-linux ];
      script      = ''
        if [ ! -f ${lib.escapeShellArg cfg.passwordFile} ]; then
          exit 0
        fi
        password=$(cat ${lib.escapeShellArg cfg.passwordFile})
        uid=$(id -u ${lib.escapeShellArg username})
        bus="unix:path=/run/user/$uid/bus"
        runtime="/run/user/$uid"
        home="/home/${lib.escapeShellArg username}"

        # Wait up to 60s for the user session D-Bus socket.
        # Auto-login: socket appears within a few seconds of graphical.target.
        i=0
        while [ ! -S "/run/user/$uid/bus" ] && [ "$i" -lt 60 ]; do
          sleep 1
          i=$((i + 1))
        done
        if [ ! -S "/run/user/$uid/bus" ]; then
          echo "User session bus not available after 60s — skipping RDP setup" >&2
          exit 0
        fi

        runuser -u ${lib.escapeShellArg username} -- \
          env HOME="$home" DBUS_SESSION_BUS_ADDRESS="$bus" XDG_RUNTIME_DIR="$runtime" \
          grdctl rdp enable
        runuser -u ${lib.escapeShellArg username} -- \
          env HOME="$home" DBUS_SESSION_BUS_ADDRESS="$bus" XDG_RUNTIME_DIR="$runtime" \
          grdctl rdp set-credentials ${lib.escapeShellArg username} "$password"
        runuser -u ${lib.escapeShellArg username} -- \
          env HOME="$home" DBUS_SESSION_BUS_ADDRESS="$bus" XDG_RUNTIME_DIR="$runtime" \
          grdctl rdp disable-view-only
      '';
      serviceConfig = {
        Type            = "oneshot";
        RemainAfterExit = true;
      };
    };
  };
}
