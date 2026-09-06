# modules/network-killswitch-stateless.nix
# VPN kill switch for the stateless role.
#
# Blocks all clearnet egress when no VPN tunnel is active.
# Implemented as an iptables OUTPUT chain — consistent with the iptables
# backend used by the rest of this project (network-desktop.nix extraCommands).
#
# Tunnel interfaces (provider-agnostic — no config change needed to switch provider):
#   - tun+      OpenVPN tunnel — PIA, NordVPN, Mullvad, ProtonVPN, ExpressVPN,
#               Surfshark, IPVanish, and any custom GUI app using .ovpn files
#   - wg+       WireGuard tunnel — Mullvad (wg-mullvad), ProtonVPN, Surfshark,
#               and any standard wg-quick setup
#   - nordlynx  NordVPN NordLynx — WireGuard impl that creates 'nordlynx', not wg+
#   - tailscale0 Tailscale — enabled system-wide in network.nix
#
# Bootstrap ports (allowed to any destination — required for region switching):
#   - UDP 1194 / TCP 443  Standard OpenVPN ports (NordVPN, Mullvad, ProtonVPN, etc.)
#   - UDP 1197 / UDP 1198 / TCP 501 / TCP 502  PIA-specific OpenVPN ports
#   - UDP 51820           Standard WireGuard port (NordLynx, ProtonVPN, Surfshark)
#   - UDP 41641           Tailscale WireGuard data plane
#
# TCP 443 trade-off: allowing TCP 443 as a bootstrap port also permits outbound
# HTTPS connections when the VPN is down. This is an inherent limitation of any
# kill switch that supports TCP-mode VPNs without pinning specific server IPs.
# UDP mode (the default for all providers above) is not affected — UDP 443 is
# not opened. Use UDP mode unless on a network that blocks UDP.
#
# LAN carve-out: RFC1918, link-local, and multicast destinations are always
# allowed so LAN devices (NAS, printers, etc.) stay reachable regardless of VPN
# state. Only local-scope destinations are permitted — never routable public IPs.
#
# DNS leaks: no clearnet DNS leak. DNS is port 53 — not on any port allow list,
# so DNS to routable servers hits the DROP rule when the VPN is down. DNS to a
# LAN resolver (matched by the RFC1918 carve-out) does succeed while the VPN is
# down; this is the accepted trade-off of "allow LAN" mode.
#
# IPv6: disabled entirely. No major commercial VPN provider tunnels IPv6 over
# OpenVPN, so an active IPv6 stack would bypass the tunnel entirely.
{ ... }:
{
  # ── IPv6 leak prevention ───────────────────────────────────────────────────
  # PIA's OpenVPN tunnels IPv4 only. An active IPv6 stack would send traffic
  # directly over the physical interface, bypassing the VPN entirely.
  networking.enableIPv6 = false;

  # ── Kill switch ────────────────────────────────────────────────────────────
  networking.firewall.extraCommands = ''
    # Create (or flush if existing) the kill switch chain.
    iptables -N vpn-kill-switch 2>/dev/null || iptables -F vpn-kill-switch

    # Always allow loopback.
    iptables -A vpn-kill-switch -o lo -j ACCEPT

    # Allow already-established connections so an in-flight transfer is not
    # severed mid-stream when the VPN daemon briefly reconnects.
    iptables -A vpn-kill-switch -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

    # Allow DHCP so the machine obtains an IP before the VPN daemon starts.
    iptables -A vpn-kill-switch -p udp --sport 68 --dport 67 -j ACCEPT

    # ── Local network (LAN) — reachable regardless of VPN state ────────────────
    # NAS boxes and other RFC1918 hosts live on the physical LAN and are never
    # routed through the tunnel, so without these rules the terminal DROP blocks
    # every new connection to them (SMB, NFS, web UIs, mDNS discovery).
    # Trade-off: DNS to a LAN resolver (e.g. router at 192.168.1.1) also succeeds
    # when the VPN is down. This is inherent to "allow LAN" mode; public DNS
    # (port 53 to routable addresses) stays blocked by the terminal DROP.
    iptables -A vpn-kill-switch -d 10.0.0.0/8     -j ACCEPT
    iptables -A vpn-kill-switch -d 172.16.0.0/12  -j ACCEPT
    iptables -A vpn-kill-switch -d 192.168.0.0/16 -j ACCEPT
    # Link-local + multicast (mDNS 224.0.0.251, SSDP 239.255.255.250) for Avahi
    # _smb._tcp service discovery.
    iptables -A vpn-kill-switch -d 169.254.0.0/16 -j ACCEPT
    iptables -A vpn-kill-switch -d 224.0.0.0/4    -j ACCEPT

    # ── VPN bootstrap ports (any destination — required for region switching) ──
    # Standard OpenVPN (NordVPN, Mullvad, ProtonVPN, ExpressVPN, Surfshark, IPVanish).
    iptables -A vpn-kill-switch -p udp --dport 1194 -j ACCEPT
    # TCP fallback for OpenVPN. See TCP 443 trade-off note in file header.
    iptables -A vpn-kill-switch -p tcp --dport 443  -j ACCEPT
    # PIA-specific OpenVPN ports (strong and standard variants).
    iptables -A vpn-kill-switch -p udp --dport 1198 -j ACCEPT
    iptables -A vpn-kill-switch -p udp --dport 1197 -j ACCEPT
    iptables -A vpn-kill-switch -p tcp --dport 502  -j ACCEPT
    iptables -A vpn-kill-switch -p tcp --dport 501  -j ACCEPT
    # Standard WireGuard (NordVPN NordLynx, ProtonVPN, Surfshark, Mullvad).
    iptables -A vpn-kill-switch -p udp --dport 51820 -j ACCEPT
    # Tailscale bootstrap (Tailscale is enabled system-wide in network.nix).
    iptables -A vpn-kill-switch -p udp --dport 41641 -j ACCEPT

    # ── VPN tunnel interfaces ──────────────────────────────────────────────────
    iptables -A vpn-kill-switch -o tun+        -j ACCEPT
    iptables -A vpn-kill-switch -o wg+         -j ACCEPT
    iptables -A vpn-kill-switch -o nordlynx    -j ACCEPT
    iptables -A vpn-kill-switch -o tailscale0  -j ACCEPT

    # Kill switch: drop all remaining clearnet egress.
    iptables -A vpn-kill-switch -j DROP

    # Jump from OUTPUT to the kill switch chain (idempotent).
    iptables -C OUTPUT -j vpn-kill-switch 2>/dev/null \
      || iptables -A OUTPUT -j vpn-kill-switch
  '';

  networking.firewall.extraStopCommands = ''
    iptables -D OUTPUT -j vpn-kill-switch 2>/dev/null || true
    iptables -F vpn-kill-switch            2>/dev/null || true
    iptables -X vpn-kill-switch            2>/dev/null || true
  '';
}
