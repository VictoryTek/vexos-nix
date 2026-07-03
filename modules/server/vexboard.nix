# modules/server/vexboard.nix
# VexBoard — self-hosted server dashboard for VexOS Server.
# Opt-in: enabled automatically by `just enable <service>` when the first service is enabled.
# Enable/disable in /etc/nixos/server-services.nix:
#   vexos.server.vexboard.enable = true;   # or false to suppress
#
# Web UI:  http://<server-ip>:7280
# Service: vexboard.service
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.vexboard;
in
{
  options.vexos.server.vexboard = {
    enable = lib.mkEnableOption "VexBoard server dashboard";

    port = lib.mkOption {
      type = lib.types.port;
      default = 7280;
      description = "Port VexBoard listens on.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open the firewall for VexBoard's port. Defaults to true — VexBoard is the server dashboard and is intended to be reachable on the LAN.";
    };

    secretFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to an env file containing VEXBOARD_AUTH__SECRET=<secret>.
        The file is loaded as a systemd EnvironmentFile; each line must be KEY=VALUE.
        Generate and write with:
          echo "VEXBOARD_AUTH__SECRET=$(openssl rand -base64 48)" \
            > /etc/nixos/secrets/vexboard-secret
          chmod 0600 /etc/nixos/secrets/vexboard-secret
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.secretFile != null;
        message = ''
          vexos.server.vexboard.secretFile must be set before enabling VexBoard.
          Generate a secret file (KEY=VALUE format required by systemd EnvironmentFile):
            echo "VEXBOARD_AUTH__SECRET=$(openssl rand -base64 48)" \
              > /etc/nixos/secrets/vexboard-secret
            chmod 0600 /etc/nixos/secrets/vexboard-secret
          Then add to your config:  vexos.server.vexboard.secretFile = "/etc/nixos/secrets/vexboard-secret";
          (Skip this if vexos.secrets.backend = "sops" — the secret is generated
          automatically on first activation instead.)
        '';
      }
    ];

    # Auto-generate the secret file on first activation when using the plaintext
    # backend, so enabling VexBoard doesn't require a manual openssl step. Under
    # the sops backend, secrets-sops.nix forces secretFile to a sops-managed path
    # that sops-nix itself populates at activation, so this is skipped.
    system.activationScripts.vexboardSecret =
      lib.mkIf (config.vexos.secrets.backend != "sops") ''
        if [ ! -e "${cfg.secretFile}" ]; then
          mkdir -p "$(dirname "${cfg.secretFile}")"
          echo "VEXBOARD_AUTH__SECRET=$(${pkgs.openssl}/bin/openssl rand -base64 48)" \
            > "${cfg.secretFile}"
          chmod 0600 "${cfg.secretFile}"
        fi
      '';

    services.vexboard = {
      enable = true;
      port = cfg.port;
      openFirewall = cfg.openFirewall;
      secretFile = cfg.secretFile;

      # Supply defaults for all required config sections that the upstream module's
      # baseConfig does not cover. Values mirror config/default.toml from the vexboard
      # source. Without these the binary fails immediately with "missing configuration
      # field" because the systemd WorkingDirectory is / so config/default.toml is
      # never found at the relative path the binary looks for.
      settings = {
        auth = {
          # Placeholder — override by setting vexos.server.vexboard.secretFile to a
          # file containing: VEXBOARD_AUTH__SECRET=<your-secret>
          # Generate: openssl rand -base64 48
          secret = "change-me-set-vexos.server.vexboard.secretFile";
          session_ttl_hours = 168;
        };
        discovery = {
          enabled = true;
          interval_secs = 60;
          server_services_only = true;
          exclude_units = [
            "systemd-*.service"
            "user@*.service"
            "getty@*.service"
            "dbus.service"
            "NetworkManager.service"
            "NetworkManager-wait-online.service"
            "NetworkManager-dispatcher.service"
            "wpa_supplicant.service"
            "ModemManager.service"
            "firewall.service"
            "nftables.service"
            "iptables.service"
            "cups.service"
            "cups-browsed.service"
            "avahi-daemon.service"
            "nscd.service"
            "bluetooth.service"
            "rtkit-daemon.service"
            "display-manager.service"
            "colord.service"
            "plymouth-*.service"
            "kmod-static-nodes.service"
            "polkit.service"
            "apparmor.service"
            "accounts-daemon.service"
            "udisks2.service"
            "upower.service"
            "acpid.service"
            "power-profiles-daemon.service"
            "bolt.service"
            "libvirtd.service"
            "libvirt-guests.service"
            "rpcbind.service"
            "rpc-statd-notify.service"
            "flatpak-*.service"
            "nix-daemon.service"
            "cpufreq.service"
            "scx.service"
            "samba-wsdd.service"
            "logrotate-checkconf.service"
          ];
        };
        docker = {
          enabled = true;
          interval_secs = 60;
          sockets = [
            "/var/run/docker.sock"
            "/run/podman/podman.sock"
          ];
          exclude_images = [ ];
        };
        probe = {
          default_interval_secs = 30;
          timeout_secs = 5;
          max_history = 100;
        };
        metrics.push_interval_ms = 2000;
      };
    };
  };
}
