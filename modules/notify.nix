# modules/notify.nix
# System event notifications via ntfy (modules/server/ntfy.nix or any ntfy topic).
# Applies to all hosts — vexos-update (modules/nix.nix) calls vexos-notify
# regardless of role, so this is imported by every configuration-*.nix, the same
# way modules/nix.nix itself is.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.notify;

  notifyScript =
    if cfg.ntfyUrl == null then
      pkgs.writeShellScriptBin "vexos-notify" ''
        exit 0
      ''
    else
      pkgs.writeShellScriptBin "vexos-notify" ''
        set -uo pipefail
        MESSAGE="''${1:-}"
        TITLE="''${2:-VexOS}"
        curl -sf -X POST \
          -H "X-Title: $TITLE" \
          ${lib.optionalString (cfg.tokenFile != null)
            ''-H "Authorization: Bearer $(cat ${cfg.tokenFile})" \''}
          -d "$MESSAGE" \
          "${cfg.ntfyUrl}" >/dev/null 2>&1 || true
        exit 0
      '';
in
{
  options.vexos.notify = {
    ntfyUrl = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Full ntfy topic URL to publish system event notifications to, e.g.
        "http://<server-ip>:2586/vexos-alerts" for the self-hosted
        vexos.server.ntfy server, or "https://ntfy.sh/<random-topic>" for the
        public instance. Leave null to disable notifications entirely —
        vexos-notify becomes a no-op.
      '';
    };

    tokenFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to a file containing an ntfy access token, sent as an
        "Authorization: Bearer" header. Required when ntfyUrl points at a
        vexos.server.ntfy instance, which defaults to auth-default-access =
        "deny-all". Generate one on the ntfy host with:
          ntfy token add <username>
        ntfy has no declarative token-creation mechanism, so this step is
        always manual.
      '';
    };
  };

  config = {
    environment.systemPackages = [ notifyScript ];

    # Generic failure-notification template — any unit can opt in with:
    #   onFailure = [ "notify-failure@<name>.service" ];
    systemd.services."notify-failure@" = {
      description = "Send an ntfy notification that %i failed";
      serviceConfig = {
        Type = "oneshot";
        # %i and %H are systemd unit specifiers (instance name, hostname) —
        # expanded by systemd itself, no shell/command-substitution needed.
        ExecStart = ''${notifyScript}/bin/vexos-notify "%i failed on %H"'';
      };
    };
  };
}
