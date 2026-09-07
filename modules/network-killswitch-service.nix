# modules/network-killswitch-service.nix
# Toggleable VPN kill switch for desktop and HTPC roles.
#
# Wraps the same iptables OUTPUT chain rules as network-killswitch-stateless.nix
# in a systemd oneshot service so the kill switch can be enabled and disabled at
# runtime without a rebuild:
#
#   systemctl start vpn-kill-switch   — enable
#   systemctl stop  vpn-kill-switch   — disable
#   just enable-kill-switch           — convenience alias
#   just disable-kill-switch          — convenience alias
#
# The vex-vpn GUI app calls start/stop via D-Bus (systemd Manager interface) to
# drive this service from its kill switch toggle button.
#
# PartOf = firewall.service: if the firewall restarts during a nixos-rebuild switch,
# this service is also restarted so the rules are re-applied after the new firewall
# rules load. The service is NOT wantedBy anything — it stays stopped until the user
# (or the app) explicitly starts it.
#
# See network-killswitch-stateless.nix for the always-on stateless variant and for
# full comments on each rule's rationale.
{ pkgs, ... }:
let
  ipt = "${pkgs.iptables}/bin/iptables";
  startScript = pkgs.writeShellScript "vpn-kill-switch-start" ''
    ${ipt} -N vpn-kill-switch 2>/dev/null || ${ipt} -F vpn-kill-switch
    ${ipt} -A vpn-kill-switch -o lo -j ACCEPT
    ${ipt} -A vpn-kill-switch -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    ${ipt} -A vpn-kill-switch -p udp --sport 68 --dport 67 -j ACCEPT
    # Tunnel interfaces MUST precede the DNS guard — a VPN-pushed resolver is
    # often RFC1918, so tunnelled DNS has to match here first.
    ${ipt} -A vpn-kill-switch -o tun+       -j ACCEPT
    ${ipt} -A vpn-kill-switch -o wg+        -j ACCEPT
    ${ipt} -A vpn-kill-switch -o nordlynx   -j ACCEPT
    ${ipt} -A vpn-kill-switch -o tailscale0 -j ACCEPT
    # DNS bootstrap (fixed resolvers only): narrow exception so NM-openvpn can
    # resolve a hostname-based VPN server before any tunnel interface exists.
    # Unlike the stateless variant, this role does NOT force the wired
    # connection's DNS to these IPs (see network.nix's forceFixedDns) — doing so
    # unconditionally here would silently change default DNS behaviour on every
    # desktop/htpc host that has this toggleable capability, even if the kill
    # switch is never started. So this firewall hole alone does not guarantee
    # bootstrap succeeds: it only helps if the host's active connection is
    # already configured to query 1.1.1.1/9.9.9.9 (e.g. via
    # vexos.network.staticWired.dns, or a manual nmcli DNS override).
    ${ipt} -A vpn-kill-switch -p udp --dport 53 -d 1.1.1.1 -j ACCEPT
    ${ipt} -A vpn-kill-switch -p udp --dport 53 -d 9.9.9.9 -j ACCEPT
    ${ipt} -A vpn-kill-switch -p tcp --dport 53 -d 1.1.1.1 -j ACCEPT
    ${ipt} -A vpn-kill-switch -p tcp --dport 53 -d 9.9.9.9 -j ACCEPT
    # DNS guard MUST precede the LAN carve-out, or the LAN rules would cover the
    # router's resolver and re-open clearnet browsing with no VPN up.
    ${ipt} -A vpn-kill-switch -p udp --dport 53 -j DROP
    ${ipt} -A vpn-kill-switch -p tcp --dport 53 -j DROP
    # Local network (LAN) — reachable regardless of VPN state.
    ${ipt} -A vpn-kill-switch -d 10.0.0.0/8     -j ACCEPT
    ${ipt} -A vpn-kill-switch -d 172.16.0.0/12  -j ACCEPT
    ${ipt} -A vpn-kill-switch -d 192.168.0.0/16 -j ACCEPT
    ${ipt} -A vpn-kill-switch -d 169.254.0.0/16 -j ACCEPT
    ${ipt} -A vpn-kill-switch -d 224.0.0.0/4    -j ACCEPT
    # VPN bootstrap ports. TCP 443 is deliberately absent — see
    # network-killswitch-stateless.nix header.
    ${ipt} -A vpn-kill-switch -p udp --dport 1194  -j ACCEPT
    ${ipt} -A vpn-kill-switch -p udp --dport 1198  -j ACCEPT
    ${ipt} -A vpn-kill-switch -p udp --dport 1197  -j ACCEPT
    ${ipt} -A vpn-kill-switch -p tcp --dport 502   -j ACCEPT
    ${ipt} -A vpn-kill-switch -p tcp --dport 501   -j ACCEPT
    ${ipt} -A vpn-kill-switch -p udp --dport 51820 -j ACCEPT
    ${ipt} -A vpn-kill-switch -p udp --dport 41641 -j ACCEPT
    ${ipt} -A vpn-kill-switch -j DROP
    ${ipt} -C OUTPUT -j vpn-kill-switch 2>/dev/null \
      || ${ipt} -A OUTPUT -j vpn-kill-switch
  '';
  stopScript = pkgs.writeShellScript "vpn-kill-switch-stop" ''
    ${ipt} -D OUTPUT -j vpn-kill-switch 2>/dev/null || true
    ${ipt} -F vpn-kill-switch            2>/dev/null || true
    ${ipt} -X vpn-kill-switch            2>/dev/null || true
  '';
in
{
  networking.enableIPv6 = false;

  systemd.services.vpn-kill-switch = {
    description = "VPN kill switch — blocks clearnet egress when no VPN tunnel is active";
    after  = [ "firewall.service" ];
    partOf = [ "firewall.service" ];
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
      ExecStart       = startScript;
      ExecStop        = stopScript;
    };
  };

  # Allow the active user to toggle the kill switch without a sudo prompt.
  # Scoped to this exact unit name and only start/stop verbs.
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id === "org.freedesktop.systemd1.manage-units" &&
          subject.isInGroup("users") &&
          action.lookup("unit") === "vpn-kill-switch.service" &&
          (action.lookup("verb") === "start" ||
           action.lookup("verb") === "stop")) {
        return polkit.Result.YES;
      }
    });
  '';
}
