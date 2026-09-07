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
#   - UDP 1194            Standard OpenVPN (NordVPN, Mullvad, ProtonVPN, etc.)
#   - UDP 1197 / UDP 1198 / TCP 501 / TCP 502  PIA-specific OpenVPN ports
#   - UDP 51820           Standard WireGuard (NordLynx, ProtonVPN, Surfshark)
#   - UDP 41641           Tailscale WireGuard data plane
#
# TCP 443 is deliberately NOT a bootstrap port. Allowing it to any destination
# would permit outbound HTTPS with no VPN up, and a browser using DNS-over-HTTPS
# (which talks to its resolver on port 443) could then both resolve and browse —
# defeating the kill switch even with port 53 blocked. The cost is that OpenVPN
# in TCP-443 mode cannot connect; use UDP mode (the default for every provider
# listed above) or one of the PIA TCP ports.
#
# ── RULE ORDER IS LOAD-BEARING ─────────────────────────────────────────────
# The chain is first-match-wins, and two orderings below are deliberate:
#
#   1. Tunnel-interface ACCEPTs come BEFORE the DNS guard. VPN providers
#      commonly push an RFC1918 resolver (PIA uses 10.0.0.242), so tunnelled
#      DNS must match the tunnel rule before the guard can drop it.
#   2. The DNS guard comes BEFORE the LAN carve-out. Without it the LAN
#      ACCEPT for 192.168.0.0/16 would cover the router's resolver, turning
#      the carve-out into a general-purpose public-name resolver and
#      re-opening clearnet browsing with no VPN up.
#
# LAN carve-out: RFC1918, link-local, and multicast destinations are allowed so
# LAN devices (NAS, printers) stay reachable regardless of VPN state. Only
# local-scope destinations are permitted — never routable public IPs. LAN hosts
# are reachable by IP, and by .local name via mDNS (UDP 5353, inside 224.0.0.0/4);
# resolving a LAN hostname through the router's DNS does not work while the VPN
# is down, which is the intended consequence of the DNS guard.
#
# DNS: port 53 is allowed out of a tunnel interface, or to exactly two fixed
# resolvers (1.1.1.1, 9.9.9.9) — the narrow exception needed so NM-openvpn can
# resolve a hostname-based VPN server (e.g. PIA) before any tunnel exists. The
# wired-fallback NetworkManager profile is pointed at these same two IPs via
# vexos.network.forceFixedDns (modules/network.nix), so the allowance is actually
# exercised rather than sitting inert. No other DNS reaches the LAN/router
# resolver — that is what stops the LAN carve-out from being an escape hatch.
#
# IPv6: disabled entirely. No major commercial VPN provider tunnels IPv6 over
# OpenVPN, so an active IPv6 stack would bypass the tunnel entirely.
{ ... }:
{
  # ── IPv6 leak prevention ───────────────────────────────────────────────────
  # PIA's OpenVPN tunnels IPv4 only. An active IPv6 stack would send traffic
  # directly over the physical interface, bypassing the VPN entirely.
  networking.enableIPv6 = false;

  # Point the wired-fallback NM profile's DNS at the two fixed resolvers the
  # DNS-bootstrap firewall rules below allow. See modules/network.nix.
  vexos.network.forceFixedDns = true;

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

    # ── VPN tunnel interfaces ──────────────────────────────────────────────────
    # MUST precede the DNS guard below — see "RULE ORDER IS LOAD-BEARING".
    iptables -A vpn-kill-switch -o tun+        -j ACCEPT
    iptables -A vpn-kill-switch -o wg+         -j ACCEPT
    iptables -A vpn-kill-switch -o nordlynx    -j ACCEPT
    iptables -A vpn-kill-switch -o tailscale0  -j ACCEPT

    # ── DNS bootstrap (fixed resolvers only) ────────────────────────────────────
    # Narrow exception to the DNS guard below: NM-openvpn must resolve the VPN
    # server hostname before any tunnel interface exists, so the tunnel-ACCEPT
    # rules above cannot yet match. Only these two fixed, non-LAN IPs are
    # allowed — never the LAN/router resolver, which is exactly the leak
    # 0a21f82 closed. vexos.network.forceFixedDns (set above) points the
    # wired-fallback profile's DNS at these same two IPs, so this allowance is
    # actually exercised rather than sitting inert.
    iptables -A vpn-kill-switch -p udp --dport 53 -d 1.1.1.1 -j ACCEPT
    iptables -A vpn-kill-switch -p udp --dport 53 -d 9.9.9.9 -j ACCEPT
    iptables -A vpn-kill-switch -p tcp --dport 53 -d 1.1.1.1 -j ACCEPT
    iptables -A vpn-kill-switch -p tcp --dport 53 -d 9.9.9.9 -j ACCEPT

    # ── DNS guard ──────────────────────────────────────────────────────────────
    # Any other DNS query reaching this point is not leaving via a tunnel and is
    # not one of the two fixed bootstrap resolvers above, so it is a leak.
    # Dropping it here also stops the LAN carve-out below from covering the
    # router's resolver and acting as a general-purpose public-name resolver.
    # mDNS (UDP 5353) is a different port and is unaffected.
    iptables -A vpn-kill-switch -p udp --dport 53 -j DROP
    iptables -A vpn-kill-switch -p tcp --dport 53 -j DROP

    # ── Local network (LAN) — reachable regardless of VPN state ────────────────
    # NAS boxes and other RFC1918 hosts live on the physical LAN and are never
    # routed through the tunnel, so without these rules the terminal DROP blocks
    # every new connection to them (SMB, NFS, web UIs, mDNS discovery).
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
    # PIA-specific OpenVPN ports (strong and standard variants).
    iptables -A vpn-kill-switch -p udp --dport 1198 -j ACCEPT
    iptables -A vpn-kill-switch -p udp --dport 1197 -j ACCEPT
    iptables -A vpn-kill-switch -p tcp --dport 502  -j ACCEPT
    iptables -A vpn-kill-switch -p tcp --dport 501  -j ACCEPT
    # Standard WireGuard (NordVPN NordLynx, ProtonVPN, Surfshark, Mullvad).
    iptables -A vpn-kill-switch -p udp --dport 51820 -j ACCEPT
    # Tailscale bootstrap (Tailscale is enabled system-wide in network.nix).
    iptables -A vpn-kill-switch -p udp --dport 41641 -j ACCEPT

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
