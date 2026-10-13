# modules/server/pihole.nix
# Pi-hole — network-wide DNS ad blocking, deployed either from nixpkgs
# (services.pihole-ftl + services.pihole-web, backend = "native") or as the
# upstream OCI container (backend = "docker").
#
# Native backend notes:
#   Configuration is immutable — pihole.toml is generated from Nix and the web
#   UI cannot change settings (misc.readOnly). Adlists come from
#   services.pihole-ftl.lists (Steven Black's list by default); override it in
#   your host config to change them.
#
# Web UI password:
#   On first activation a random password is written to environmentFile as
#   FTLCONF_webserver_api_password (read it with
#   `sudo cat /etc/nixos/secrets/pihole-env`). Edit that file and restart the
#   service to change it. Both backends read the same variable.
#
# DNS exposure:
#   Same model as adguard.nix — the DNS listener binds to loopback only and
#   port 53 is NOT opened by default. To serve DNS on the LAN, set:
#     vexos.server.pihole.dnsBindHosts = [ "0.0.0.0" ];   # or specific LAN IP
#     vexos.server.pihole.openDnsFirewall = true;
#
#   For recursive resolution through unbound.nix, set:
#     vexos.server.pihole.upstreams = [ "127.0.0.1#5335" ];
#   (native backend only — the container cannot reach the host's loopback).
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.pihole;

  # Any wildcard address means "listen everywhere".
  listenAll = lib.any (h: h == "0.0.0.0" || h == "::") cfg.dnsBindHosts;

  # Docker -p host address: IPv6 literals need brackets.
  publishAddr = h: if lib.hasInfix ":" h then "[${h}]" else h;
in
{
  options.vexos.server.pihole = {
    enable = lib.mkEnableOption "Pi-hole DNS ad blocker";

    backend = lib.mkOption {
      type = lib.types.enum [ "native" "docker" ];
      default = "native";
      description = ''
        How Pi-hole is deployed. "native" uses the nixpkgs pihole-ftl and
        pihole-web modules (configuration fully managed by Nix). "docker"
        runs the upstream pihole/pihole container, configured through the
        web UI with state under dataDir.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8053;
      description = "Port for the Pi-hole web interface (served at / on native, /admin on docker).";
    };

    dnsBindHosts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "127.0.0.1" "::1" ];
      description = ''
        Addresses Pi-hole will serve DNS on. Default is loopback only.
        Set to [ "0.0.0.0" ] (and enable openDnsFirewall) to serve DNS on
        the LAN.
      '';
    };

    openDnsFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Open TCP/UDP port 53 in the firewall. Off by default — enable
        only on hosts that are the intended LAN DNS resolver, and
        consider scoping to a specific interface in your host config.
      '';
    };

    upstreams = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "9.9.9.9" "149.112.112.112" ];
      description = ''
        Upstream DNS servers ("ip" or "ip#port"). Default is Quad9.
      '';
    };

    environmentFile = lib.mkOption {
      type = lib.types.str;
      default = "/etc/nixos/secrets/pihole-env";
      description = ''
        systemd EnvironmentFile holding FTLCONF_webserver_api_password.
        Generated with a random password on first activation if missing.
      '';
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/pihole-docker";
      description = ''
        Docker backend only: host directory bind-mounted to /etc/pihole
        (configuration, gravity database, query log). The native backend
        keeps its state in /var/lib/pihole.
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open the firewall for the Pi-hole web interface port.";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      vexos.server.backup.servicePaths.pihole =
        if cfg.backend == "native" then [ "/var/lib/pihole" ] else [ cfg.dataDir ];

      assertions = [
        {
          assertion = !config.vexos.server.adguard.enable;
          message = "vexos.server.pihole and vexos.server.adguard both serve DNS on port 53 — enable only one of them.";
        }
        {
          assertion = cfg.backend != "docker" || !config.vexos.server.podman.enable;
          message = "vexos.server.pihole.backend = \"docker\" conflicts with vexos.server.podman.enable = true — Podman forces Docker off. Use vexos.server.pihole.backend = \"native\" instead.";
        }
      ];

      # Generate the web UI password on first activation so enabling Pi-hole
      # never leaves the admin UI unauthenticated.
      system.activationScripts.piholeSecret = ''
        if [ ! -e "${cfg.environmentFile}" ]; then
          mkdir -p "$(dirname "${cfg.environmentFile}")"
          ( umask 077
            echo "FTLCONF_webserver_api_password=$(${pkgs.openssl}/bin/openssl rand -hex 16)" \
              > "${cfg.environmentFile}" )
        fi
      '';

      networking.firewall.allowedTCPPorts =
        lib.optional cfg.openFirewall cfg.port
        ++ lib.optional cfg.openDnsFirewall 53;
      networking.firewall.allowedUDPPorts = lib.optional cfg.openDnsFirewall 53;
    }

    (lib.mkIf (cfg.backend == "native") {
      services.pihole-ftl = {
        enable = true;
        lists = lib.mkDefault [
          {
            url = "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts";
            description = "Steven Black's unified hosts list";
          }
        ];
        settings = {
          dns.upstreams = cfg.upstreams;
          # NONE = Pi-hole writes no listening directives, so the explicit
          # bind-interfaces/listen-address lines below decide the sockets.
          dns.listeningMode = if listenAll then "ALL" else "NONE";
          misc.dnsmasq_lines = lib.optionals (!listenAll)
            ([ "bind-interfaces" ] ++ map (h: "listen-address=${h}") cfg.dnsBindHosts);
        };
      };

      services.pihole-web = {
        enable = true;
        ports = [ cfg.port ];
      };

      systemd.services.pihole-ftl.serviceConfig.EnvironmentFile = cfg.environmentFile;
    })

    (lib.mkIf (cfg.backend == "docker") {
      virtualisation.docker.enable = lib.mkDefault true;
      virtualisation.oci-containers.backend = lib.mkDefault "docker";

      systemd.tmpfiles.rules = [ "d ${cfg.dataDir} 0750 root root -" ];

      virtualisation.oci-containers.containers.pihole = {
        image = "pihole/pihole:2026.09.0";
        ports = [ "${toString cfg.port}:80/tcp" ]
          ++ lib.concatMap
            (h: [ "${publishAddr h}:53:53/tcp" "${publishAddr h}:53:53/udp" ])
            cfg.dnsBindHosts;
        environment = {
          TZ = config.time.timeZone;
          # Queries arrive from the Docker bridge gateway, not a local subnet.
          FTLCONF_dns_listeningMode = "ALL";
          FTLCONF_dns_upstreams = lib.concatStringsSep ";" cfg.upstreams;
        };
        environmentFiles = [ cfg.environmentFile ];
        volumes = [ "${cfg.dataDir}:/etc/pihole" ];
      };
    })
  ]);
}
