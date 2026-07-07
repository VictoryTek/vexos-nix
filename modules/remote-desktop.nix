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
# Keyring self-heal (auto-login never supplies a password to PAM, so
# pam_gnome_keyring can never unlock or create the "login" collection on its own):
#   Before calling grdctl, this service runs `gnome-keyring-daemon --unlock --replace`
#   with an empty stdin password, targeting the same session bus as the grdctl calls
#   below. That call creates the "login" collection with an empty password if it's
#   missing, or unlocks it if it already has one — idempotently, on every run. No
#   manual keyring reset is required on any machine.
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
      path        = [ pkgs.gnome-remote-desktop pkgs.gnome-keyring pkgs.coreutils pkgs.util-linux ];
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

        # Self-heal the GNOME Keyring "login" collection: create it with an empty
        # password if missing, or unlock it if already empty-password. Idempotent —
        # safe to run on every service start. Non-fatal if the user has set a real
        # keyring password (unlock just fails; existing contents are untouched).
        # NOTE: must be a real newline (empty *line*), not zero bytes — piping
        # `printf ""` sends immediate EOF with no data, which gnome-keyring-daemon
        # reads as "no password supplied" and silently skips creating the
        # collection entirely (verified against journalctl/dbus on vexos-vmc).
        printf "\n" | runuser -u ${lib.escapeShellArg username} -- \
          env HOME="$home" DBUS_SESSION_BUS_ADDRESS="$bus" XDG_RUNTIME_DIR="$runtime" \
          gnome-keyring-daemon --unlock --replace --components=secrets,pkcs11,ssh >/dev/null || true

        # Small buffer plus retry on set-credentials, kept as defense-in-depth
        # against any remaining startup latency.
        sleep 2

        runuser -u ${lib.escapeShellArg username} -- \
          env HOME="$home" DBUS_SESSION_BUS_ADDRESS="$bus" XDG_RUNTIME_DIR="$runtime" \
          grdctl rdp enable

        cred_ok=0
        for attempt in 1 2 3 4 5; do
          if runuser -u ${lib.escapeShellArg username} -- \
            env HOME="$home" DBUS_SESSION_BUS_ADDRESS="$bus" XDG_RUNTIME_DIR="$runtime" \
            grdctl rdp set-credentials ${lib.escapeShellArg username} "$password"; then
            cred_ok=1
            break
          fi
          sleep 1
        done
        if [ "$cred_ok" -ne 1 ]; then
          echo "grdctl rdp set-credentials failed after 5 attempts" >&2
        fi

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
