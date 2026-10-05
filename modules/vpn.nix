# modules/vpn.nix
# PIA VPN (WireGuard primary, OpenVPN backup) + nftables kill switch.
# Imported by: configuration-desktop.nix, configuration-htpc.nix,
#              configuration-stateless.nix (+ modules/vpn-stateless.nix).
# Design: .github/docs/subagent_docs/stateless_vpn_redesign_spec.md
#
# The tunnel is owned by a systemd service (vexos-vpn.service), not by
# NetworkManager/GNOME. NetworkManager still manages Ethernet and Wi-Fi; the
# tunnel sits on top of whatever link is up, so every role works wired or
# wireless on any hardware.
#
# Kill switch (vexos-killswitch.service) — an allow-list, default drop:
#   • the tunnel interfaces (and tailscale0, whose own traffic is routed into
#     the tunnel while the kill switch is on — see ksStart below)
#   • packets carrying the tunnel's fwmark (0x5650), only to PIA server IPs.
#     Only CAP_NET_ADMIN processes can set a mark, and WireGuard/OpenVPN mark
#     their own encrypted packets, so no application can use this exit.
#   • root-only HTTPS to PIA server IPs (token / addKey / latency probes)
#   • DHCP, and optionally the LAN (minus DNS ports, so the router's resolver
#     can never be used to look up public names)
# No DNS ever leaves outside the tunnel; PIA endpoints are addressed by IP.
#
#   vexos-vpn status | up | down | region <id|auto> | protocol <wg|openvpn>
#   vexos-vpn killswitch on|off   — off asks for a password in "always" mode
#   sudo vexos-vpn login          — store PIA credentials (root-only file)
#
# Everything here is gated by vexos.features.vpn.enable (default off). Desktop
# and htpc opt in via /etc/nixos/features.nix (`just feature enable vpn`);
# stateless forces it on in modules/vpn-stateless.nix.
#
# The vex-vpn GUI + tray (flake input `vex-vpn`; its module is imported by
# flake.nix as vexVpnModule) is installed alongside when the VPN is enabled, so
# the VPN has full GUI control: connect, region, protocol, kill switch, and PIA
# sign-in. The CLI above is the backup.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.vpn;
  vpn = pkgs.vexos.vexos-vpn;
  always = cfg.killSwitch.mode == "always";

  # Keep in sync with pkgs/vexos-vpn/vexos-vpn.sh (FWMARK / TABLE / iface names).
  fwmark = "0x5650";
  table = "22096";
  lan = "{ 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 169.254.0.0/16, 224.0.0.0/4 }";

  # Atomic, idempotent replace: the first two lines make `nft -f` succeed
  # whether or not the table already exists, and the whole file is one
  # transaction — there is no instant where the old rules are gone and the new
  # ones are not yet loaded.
  ksRuleset = pkgs.writeText "vexos-killswitch.nft" ''
    table inet vexos_killswitch
    delete table inet vexos_killswitch
    table inet vexos_killswitch {
      # Every PIA meta/wg/openvpn IP; filled from the cached server list by
      # `vexos-vpn killswitch sync` (and refreshed after each connect).
      set pia_servers { type ipv4_addr; }
      # Transient, self-expiring entries for the server-list bootstrap.
      set bootstrap { type ipv4_addr; flags timeout; }

      chain output {
        type filter hook output priority filter; policy drop;

        oifname "lo" accept
        meta nfproto ipv6 drop
        ct state established,related accept

        oifname { "pia0", "pia0-ovpn", "tailscale0" } accept

        meta mark ${fwmark} ip daddr @pia_servers accept
        meta skuid 0 ip daddr @pia_servers tcp dport { 443, 1337 } accept
        meta skuid 0 ip daddr @bootstrap udp dport 53 accept
        meta skuid 0 ip daddr @bootstrap tcp dport { 53, 443 } accept

        udp sport 68 udp dport 67 accept
    ${lib.optionalString cfg.killSwitch.allowLan ''
        # LAN (NAS, printers, SMB discovery via mDNS 224.0.0.251:5353) — but
        # never DNS/DoT, so the router cannot resolve public names for us.
        ip daddr ${lan} udp dport { 53, 853 } drop
        ip daddr ${lan} tcp dport { 53, 853 } drop
        ip daddr ${lan} accept
    ''}  }
    }
  '';

  ksStart = pkgs.writeShellScript "vexos-killswitch-start" ''
    set -eu
    ${pkgs.nftables}/bin/nft -f ${ksRuleset}
    # Tailscale marks its own packets 0x80000 and routes them via the main
    # table (its rule 5210), i.e. straight out the physical NIC. While the kill
    # switch is on, send them into the tunnel instead. With the tunnel down the
    # table is empty, the lookup falls through, and the kill switch drops them.
    ${pkgs.iproute2}/bin/ip -4 rule del pref 5200 2>/dev/null || true
    ${pkgs.iproute2}/bin/ip -4 rule add pref 5200 fwmark 0x80000/0xff0000 table ${table}
    ${vpn}/bin/vexos-vpn killswitch sync || true
  '';

  ksStop = pkgs.writeShellScript "vexos-killswitch-stop" ''
    ${pkgs.iproute2}/bin/ip -4 rule del pref 5200 2>/dev/null || true
    ${pkgs.nftables}/bin/nft delete table inet vexos_killswitch 2>/dev/null || true
  '';
in
{
  options.vexos.features.vpn.enable = lib.mkEnableOption "PIA VPN (WireGuard/OpenVPN) with nftables kill switch and the vex-vpn GUI";

  options.vexos.vpn = {
    protocol = lib.mkOption {
      type = lib.types.enum [ "wireguard" "openvpn" ];
      default = "wireguard";
      description = "Default tunnel protocol. `vexos-vpn protocol` overrides it at runtime.";
    };
    region = lib.mkOption {
      type = lib.types.strMatching "[a-z0-9_-]+";
      default = "auto";
      description = ''
        Default PIA region id (see `vexos-vpn regions`), or "auto" for the
        lowest-latency region. `vexos-vpn region` overrides it at runtime.
      '';
    };
    autoConnect = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Start the VPN at boot.";
    };
    credentialsFile = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/vexos-vpn/credentials";
      example = lib.literalExpression ''config.sops.secrets."pia-credentials".path'';
      description = ''
        File containing the PIA username (line 1) and password (line 2).
        Default is written by `sudo vexos-vpn login` (root:root 0400). May
        point at a sops-nix secret instead; `vexos-vpn login` then cannot be used.
      '';
    };
    killSwitch = {
      mode = lib.mkOption {
        type = lib.types.enum [ "off" "manual" "always" ];
        default = "manual";
        description = ''
          off    — no kill switch.
          manual — available, stopped at boot; toggle with `vexos-vpn killswitch on|off`.
          always — loaded before any network comes up; NetworkManager refuses
                   to start without it. Turning it off at runtime asks for an
                   admin password and lasts until the next boot.
        '';
      };
      allowLan = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Allow RFC1918, link-local and multicast destinations (except DNS ports) with the kill switch on.";
      };
    };
  };

  config = lib.mkIf config.vexos.features.vpn.enable (lib.mkMerge [
    {
      environment.systemPackages = [ vpn ];

      # GUI + tray autostart; only present while the VPN itself is enabled.
      programs.vex-vpn.enable = true;

      environment.etc."vexos-vpn/config".text = ''
        DEFAULT_REGION=${lib.escapeShellArg cfg.region}
        DEFAULT_PROTOCOL=${lib.escapeShellArg cfg.protocol}
        CREDENTIALS_FILE=${lib.escapeShellArg cfg.credentialsFile}
        KILLSWITCH_MODE=${lib.escapeShellArg cfg.killSwitch.mode}
        AUTOCONNECT=${lib.boolToString cfg.autoConnect}
      '';

      # PIA tunnels IPv4 only; an active IPv6 stack would bypass the tunnel.
      networking.enableIPv6 = false;

      # Required by fwmark policy routing: replies from the tunnel endpoint
      # arrive on the physical NIC while the unmarked reverse route points into
      # the tunnel, which strict reverse-path filtering drops.
      networking.firewall.checkReversePath = "loose";

      systemd.services.vexos-vpn = {
        description = "PIA VPN tunnel (vexos-vpn)";
        wants = [ "network-online.target" ];
        after = [ "network-online.target" "systemd-resolved.service" "vexos-killswitch.service" ];
        wantedBy = lib.mkIf cfg.autoConnect [ "multi-user.target" ];
        # Keep retrying for as long as it is meant to be up (Wi-Fi not joined
        # yet, PIA briefly unreachable, …).
        unitConfig.StartLimitIntervalSec = 0;
        serviceConfig = {
          ExecStart = "${vpn}/bin/vexos-vpn daemon";
          ExecStopPost = "${vpn}/bin/vexos-vpn teardown";
          Restart = "always";
          RestartSec = 10;
          StateDirectory = "vexos-vpn";
          StateDirectoryMode = "0755"; # state.json/serverlist readable; credentials/token are 0400/0600
          RuntimeDirectory = "vexos-vpn";
          RuntimeDirectoryMode = "0755"; # status.json is read by unprivileged `vexos-vpn status`
          RuntimeDirectoryPreserve = "restart"; # keep last_error visible between retries
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
        };
      };

      # Runtime setters, startable by the users group via polkit (CLI and GUI).
      systemd.services."vexos-vpn-region@" = {
        description = "Set vexos-vpn region to %i";
        serviceConfig = { Type = "oneshot"; ExecStart = "${vpn}/bin/vexos-vpn region %i"; };
      };
      systemd.services."vexos-vpn-protocol@" = {
        description = "Set vexos-vpn protocol to %i";
        serviceConfig = { Type = "oneshot"; ExecStart = "${vpn}/bin/vexos-vpn protocol %i"; };
      };

      security.polkit.extraConfig = ''
        // vexos-vpn: let the desktop user drive the VPN without sudo.
        polkit.addRule(function(action, subject) {
          if (action.id !== "org.freedesktop.systemd1.manage-units" || !subject.isInGroup("users")) {
            return polkit.Result.NOT_HANDLED;
          }
          var unit = action.lookup("unit");
          var verb = action.lookup("verb");
          if (unit === "vexos-vpn.service" &&
              (verb === "start" || verb === "stop" || verb === "restart")) {
            return polkit.Result.YES;
          }
          if (verb === "start" &&
              /^vexos-vpn-(region@[a-z0-9_-]+|protocol@(wireguard|openvpn))\.service$/.test(unit)) {
            return polkit.Result.YES;
          }
          if (unit === "vexos-killswitch.service") {
            if (verb === "start") { return polkit.Result.YES; }
            if (verb === "stop")  { return polkit.Result.${if always then "AUTH_ADMIN_KEEP" else "YES"}; }
          }
          return polkit.Result.NOT_HANDLED;
        });
      '';
    }

    (lib.mkIf (cfg.killSwitch.mode != "off") {
      systemd.services.vexos-killswitch = {
        description = "VPN kill switch — only the PIA tunnel may reach the internet";
        before = [ "network-pre.target" ];
        wants = [ "network-pre.target" ];
        wantedBy = lib.mkIf always [ "multi-user.target" ];
        # Rebuilds swap the ruleset atomically (ExecReload) instead of
        # stop+start, so a `nixos-rebuild switch` never opens a gap.
        reloadIfChanged = true;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = ksStart;
          ExecReload = ksStart;
          ExecStop = ksStop;
        };
      };
    })

    (lib.mkIf always {
      # Fail closed: with no kill switch loaded, NetworkManager does not start,
      # so the machine never comes up online without it. Deliberately not
      # Requires= — that would also stop NetworkManager whenever the kill
      # switch is turned off at runtime.
      systemd.services.NetworkManager = {
        after = [ "vexos-killswitch.service" ];
        serviceConfig.ExecStartPre = [ "${pkgs.nftables}/bin/nft list table inet vexos_killswitch" ];
      };
    })
  ]);
}
