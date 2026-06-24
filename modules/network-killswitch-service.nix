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
    ${ipt} -A vpn-kill-switch -p udp --dport 1194  -j ACCEPT
    ${ipt} -A vpn-kill-switch -p tcp --dport 443   -j ACCEPT
    ${ipt} -A vpn-kill-switch -p udp --dport 1198  -j ACCEPT
    ${ipt} -A vpn-kill-switch -p udp --dport 1197  -j ACCEPT
    ${ipt} -A vpn-kill-switch -p tcp --dport 502   -j ACCEPT
    ${ipt} -A vpn-kill-switch -p tcp --dport 501   -j ACCEPT
    ${ipt} -A vpn-kill-switch -p udp --dport 51820 -j ACCEPT
    ${ipt} -A vpn-kill-switch -p udp --dport 41641 -j ACCEPT
    ${ipt} -A vpn-kill-switch -o tun+       -j ACCEPT
    ${ipt} -A vpn-kill-switch -o wg+        -j ACCEPT
    ${ipt} -A vpn-kill-switch -o nordlynx   -j ACCEPT
    ${ipt} -A vpn-kill-switch -o tailscale0 -j ACCEPT
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
