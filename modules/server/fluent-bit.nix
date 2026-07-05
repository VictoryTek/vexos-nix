# modules/server/fluent-bit.nix
# Fluent Bit — ships the systemd journal to the local Loki instance.
# Note: `promtail` (the tool the MASTER_PLAN originally named) was removed
# from nixpkgs as end-of-life; Fluent Bit is nixpkgs' own suggested
# lightweight replacement (the other being Grafana Alloy).
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.fluent-bit;
in
{
  options.vexos.server.fluent-bit = {
    enable = lib.mkEnableOption "Fluent Bit journal-to-Loki log shipper";
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.vexos.server.loki.enable;
        message = "vexos.server.fluent-bit.enable requires vexos.server.loki.enable = true — Fluent Bit ships journal logs to the local Loki instance and has nowhere else to send them.";
      }
    ];

    systemd.tmpfiles.rules = [
      "d /var/lib/fluent-bit 0700 root root -"
    ];

    services.fluent-bit = {
      enable = true;
      settings = {
        service = {
          flush = 1;
          log_level = "info";
        };

        pipeline = {
          inputs = [
            {
              name = "systemd";
              tag = "host.*";
              read_from_tail = true;
              strip_underscores = true;
              db = "/var/lib/fluent-bit/systemd.db";
            }
          ];

          outputs = [
            {
              name = "loki";
              match = "*";
              host = "localhost";
              port = 3100;
              labels = "job=fluent-bit, host=${config.networking.hostName}";
              label_keys = "$SYSTEMD_UNIT";
            }
          ];
        };
      };
    };
  };
}
