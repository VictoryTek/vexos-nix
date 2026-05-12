# modules/server/kiji-proxy.nix
# Kiji Privacy Proxy — local PII-masking proxy for AI API requests.
# Intercepts outbound requests to OpenAI/Anthropic/etc., replaces personally
# identifiable information with dummy values using a local ONNX ML model, and
# restores the originals in responses.  All inference runs on-device; no data
# leaves the machine for PII detection.
#
# Default port  : 8080  (forward proxy + REST API + health endpoint)
# Health check  : curl http://localhost:8080/health
# Usage         : set HTTP_PROXY=http://127.0.0.1:<port> in client env
#
# Environment file (optional, set via environmentFile option):
#   OPENAI_API_KEY=sk-...
#   LOG_PII_CHANGES=true
#   # PROXY_PORT is set automatically from the port option
#
# ⚠ The package hash in pkgs/kiji-proxy/default.nix is set automatically by
#   `just enable kiji-proxy`.  See that file if you need to set it manually.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.kiji-proxy;
in
{
  options.vexos.server.kiji-proxy = {
    enable = lib.mkEnableOption "Kiji Privacy Proxy PII-masking AI gateway";

    port = lib.mkOption {
      type        = lib.types.port;
      default     = 8080;
      description = "Port the proxy listens on (forward proxy + health API).";
    };

    environmentFile = lib.mkOption {
      type        = lib.types.str;
      default     = "";
      description = ''
        Path to a file containing environment variables loaded into the service,
        e.g. OPENAI_API_KEY or LOG_PII_CHANGES.  Leave empty if not needed.
        The file should not be world-readable (chmod 600 recommended).
      '';
    };
  };

  config = lib.mkIf cfg.enable {

    users.groups.kiji-proxy = {};
    users.users.kiji-proxy = {
      isSystemUser = true;
      group        = "kiji-proxy";
      description  = "Kiji Privacy Proxy service user";
    };

    systemd.services.kiji-proxy = {
      description = "Kiji Privacy Proxy";
      after       = [ "network.target" ];
      wantedBy    = [ "multi-user.target" ];

      serviceConfig = {
        Type            = "simple";
        User            = "kiji-proxy";
        Group           = "kiji-proxy";
        ExecStart       = "${pkgs.vexos.kiji-proxy}/bin/kiji-proxy";
        Environment     = [
          "LD_LIBRARY_PATH=${pkgs.vexos.kiji-proxy}/lib"
          "PROXY_PORT=:${toString cfg.port}"
        ];
        Restart         = "on-failure";
        RestartSec      = "5s";
        StandardOutput  = "journal";
        StandardError   = "journal";
      } // lib.optionalAttrs (cfg.environmentFile != "") {
        EnvironmentFile = cfg.environmentFile;
      };
    };

    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
