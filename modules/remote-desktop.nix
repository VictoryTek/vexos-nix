# modules/remote-desktop.nix
# Automatic GNOME Remote Desktop (RDP) TLS + credential setup.
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
#
# TLS certificate (why RDP never connected before this existed):
#   gnome-remote-desktop speaks RDP over TLS only, and does not generate its own
#   certificate. Its startup gate — maybe_start_rdp_server() in src/grd-daemon.c —
#   calls start_rdp_server() only when BOTH the tls-cert and tls-key GSettings keys
#   are non-empty; otherwise it logs "RDP TLS certificate and key not yet configured
#   properly" and never opens a listening socket. Both keys default to '' upstream.
#   With RDP "enabled" but no certificate, nothing ever listens on 3389, so every
#   client (Remmina, mstsc) fails to *connect* — not to authenticate.
#   This service therefore generates a self-signed cert once per host and registers
#   it with grdctl before enabling RDP.
{ config, lib, pkgs, ... }:
let
  cfg      = config.vexos.remoteDesktop;
  username = config.vexos.user.name;

  # Runtime-generated, never in the Nix store (a private key must not be
  # world-readable). /var/lib is persistent on every role that imports this
  # module — stateless (impermanence) does not import it.
  certDir  = "/var/lib/vexos-rdp";
  certFile = "${certDir}/tls.crt";
  keyFile  = "${certDir}/tls.key";
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
      description = "Configure GNOME Remote Desktop TLS certificate and credentials";
      wantedBy    = [ "graphical.target" ];
      after       = [ "graphical.target" "dbus.service" ];
      path        = [ pkgs.gnome-remote-desktop pkgs.gnome-keyring pkgs.coreutils pkgs.util-linux pkgs.openssl ];
      script      = ''
        if [ ! -f ${lib.escapeShellArg cfg.passwordFile} ]; then
          exit 0
        fi
        password=$(cat ${lib.escapeShellArg cfg.passwordFile})

        # Self-signed RDP TLS certificate, generated once per host. Guarded on
        # both files existing so a rebuild never rotates the certificate — that
        # would invalidate the fingerprint every client has pinned. To rotate
        # deliberately, delete both files and restart this service.
        # Owned by the vexos user: the gnome-remote-desktop user daemon runs as
        # that user and must read both.
        if [ ! -f ${certFile} ] || [ ! -f ${keyFile} ]; then
          mkdir -p ${certDir}
          chmod 700 ${certDir}
          # umask in a subshell so the key is never world-readable, not even for
          # the instant between openssl writing it and the chmod below.
          ( umask 077
            openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
              -keyout ${keyFile} -out ${certFile} \
              -subj "/CN=${config.networking.hostName}" )
        fi
        chown -R ${lib.escapeShellArg username} ${certDir}
        chmod 700 ${certDir}
        chmod 600 ${keyFile}
        chmod 644 ${certFile}

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

        # Register the TLS certificate BEFORE enabling RDP, so the daemon sees a
        # complete configuration and starts the server on the first pass.
        runuser -u ${lib.escapeShellArg username} -- \
          env HOME="$home" DBUS_SESSION_BUS_ADDRESS="$bus" XDG_RUNTIME_DIR="$runtime" \
          grdctl rdp set-tls-cert ${certFile}

        runuser -u ${lib.escapeShellArg username} -- \
          env HOME="$home" DBUS_SESSION_BUS_ADDRESS="$bus" XDG_RUNTIME_DIR="$runtime" \
          grdctl rdp set-tls-key ${keyFile}

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
