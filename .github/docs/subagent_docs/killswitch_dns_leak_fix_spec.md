# Kill Switch DNS Leak Fix — Specification

## Current State

`modules/network-killswitch-stateless.nix` (always-on, stateless) and
`modules/network-killswitch-service.nix` (toggleable, desktop/htpc) build an
identical `vpn-kill-switch` iptables OUTPUT chain. Current order:

1. `-o lo` ACCEPT
2. `ESTABLISHED,RELATED` ACCEPT
3. DHCP ACCEPT
4. **LAN destinations ACCEPT** (RFC1918 / link-local / multicast) — added in `2ee1656`
5. VPN bootstrap ports ACCEPT (UDP 1194/1197/1198/51820/41641, **TCP 443**/501/502)
6. Tunnel interfaces ACCEPT (`tun+`, `wg+`, `nordlynx`, `tailscale0`)
7. Terminal DROP

## Problem Definition

The kill switch no longer blocks clearnet. Two rules combine:

- Rule 4 permits `192.168.0.0/16`, which includes the LAN resolver the machine is
  configured to use (`vexos.network.staticWired.dns` defaults to
  `192.168.1.1`, see `modules/network.nix`). Name resolution therefore succeeds
  with no VPN up.
- Rule 5's `TCP 443 to any destination` (pre-existing OpenVPN TCP-mode bootstrap)
  then carries the actual HTTPS session.

Before `2ee1656` the chain blocked all of port 53, so TCP 443 was open but
unusable — the kill switch worked only by accident. Adding the LAN carve-out
removed that accidental protection and exposed the structural hole.

Additionally, `TCP 443` to any destination is independently sufficient for a
browser using DNS-over-HTTPS to both resolve and browse, so blocking port 53
alone does not close the leak.

## Proposed Solution Architecture

Reorder the chain and add a DNS guard, so the LAN carve-out cannot act as a
general-purpose resolver, then remove the TCP 443 bootstrap rule.

New order:

1. `-o lo` ACCEPT
2. `ESTABLISHED,RELATED` ACCEPT
3. DHCP ACCEPT
4. **Tunnel interfaces ACCEPT** (moved up from position 6)
   Must precede the DNS guard: VPN-pushed resolvers are commonly RFC1918
   (PIA uses `10.0.0.242`), so tunnelled DNS has to match here first.
5. **DNS guard: DROP `udp --dport 53` and `tcp --dport 53`** (new)
   Any DNS reaching this point is not leaving via the tunnel, so it is a leak
   and would let rule 6 resolve arbitrary public names.
6. LAN destinations ACCEPT (unchanged set: RFC1918, `169.254.0.0/16`, `224.0.0.0/4`)
   Port 53 is already gone, so LAN hosts stay reachable by IP and `.local`
   names still resolve over mDNS (UDP 5353, inside `224.0.0.0/4`).
7. VPN bootstrap ports ACCEPT — **`TCP 443` removed**; UDP 1194/1197/1198/51820/41641
   and TCP 501/502 retained.
8. Terminal DROP

### Behaviour after the change

| Scenario | Result |
|----------|--------|
| VPN down, browse a website | Blocked (no DNS, no 443) |
| VPN down, reach NAS by LAN IP | Works |
| VPN down, reach NAS by `.local` name | Works (mDNS/Avahi, UDP 5353) |
| VPN down, reach NAS by router-DNS hostname | Blocked (port 53 guard) |
| VPN up, browse | Works via tunnel |
| VPN up, tunnelled DNS to an RFC1918 resolver | Works (tunnel rule precedes guard) |
| OpenVPN connect over UDP 1194/1197/1198, WireGuard 51820, Tailscale 41641 | Works |
| OpenVPN connect over TCP 443 | No longer supported (deliberate) |

## Implementation Steps (Module Architecture Pattern — Option B)

Both files are role/feature-addition modules with no `lib.mkIf` role guards. The
change edits the existing rule strings in place; no new files, options, or
conditionals.

1. `modules/network-killswitch-stateless.nix` — reorder `extraCommands` per the
   above, add the two DNS-guard DROP lines, delete the TCP 443 ACCEPT, and
   rewrite the header comment block (the "TCP 443 trade-off" and "DNS leaks"
   paragraphs are both superseded).
2. `modules/network-killswitch-service.nix` — same reorder / additions /
   deletion inside `startScript`, using the `${ipt}` interpolation.

`extraStopCommands` / `stopScript` need no change — they flush and delete the
whole chain.

## Dependencies

None. No new flake inputs or packages. Context7 not applicable.

## Configuration Changes

None to any `configuration-*.nix`. No `system.stateVersion` change. No option
surface change.

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| OpenVPN TCP-443 mode stops working | Deliberate, user-approved. UDP modes and all WireGuard providers unaffected; UDP is the default for PIA/Mullvad/Proton/Nord |
| VPN-pushed RFC1918 DNS caught by the guard | Tunnel-interface ACCEPTs moved above the guard |
| NAS unreachable by router-DNS hostname while VPN down | mDNS `.local` names still resolve; documented in-file and in the table above |
| Rule order regression on a future edit | Order dependence called out explicitly in the in-file comments |
| Two files drift apart | Same edit applied to both in this change |
