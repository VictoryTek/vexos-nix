# Kill Switch LAN Carve-Out — Specification

## Current State Analysis

The VPN kill switch is implemented in two places with identical rule logic:

- `modules/network-killswitch-stateless.nix` — always-on for the `stateless` role,
  applied via `networking.firewall.extraCommands`.
- `modules/network-killswitch-service.nix` — toggleable `systemd` oneshot
  (`vpn-kill-switch.service`) for `desktop` and `htpc` roles.

Both build an iptables `OUTPUT`-jump chain `vpn-kill-switch` that ACCEPTs:
loopback, ESTABLISHED/RELATED, DHCP client, a fixed set of VPN bootstrap ports
(UDP 1194/1197/1198/51820/41641, TCP 443/501/502), and the tunnel interfaces
(`tun+`, `wg+`, `nordlynx`, `tailscale0`). Everything else hits a terminal `DROP`.

## Problem Definition

There is no exception for the local network. NAS boxes and other RFC1918 hosts
sit on the physical LAN and are never routed through the tunnel, so every *new*
outbound connection to them (SMB 445, NFS, web UIs, `mDNS`/SSDP discovery) matches
the terminal `DROP`. On the `stateless` role this happens unconditionally; on
desktop/htpc it happens whenever the kill switch is toggled on. Result: LAN
devices are unreachable.

## Proposed Solution Architecture

Add ACCEPT rules for private / local-scope destinations to the `vpn-kill-switch`
chain, positioned after the ESTABLISHED/RELATED rule and before the VPN bootstrap
block (order within the ACCEPT rules is immaterial; only "before the final DROP"
matters). Ranges:

- `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16` — RFC1918 unicast (NAS, hosts).
- `169.254.0.0/16` — link-local.
- `224.0.0.0/4` — multicast, covers `mDNS` (224.0.0.251) and SSDP (239.255.255.250)
  so Avahi `_smb._tcp` discovery works.

This is the standard "allow local network" kill-switch mode. It does not create a
clearnet path: only RFC1918 / link-local / multicast destinations are permitted,
never routable public IPs.

### Security note (documented in-file)

Allowing LAN egress means DNS queries to a LAN resolver (e.g. router at
`192.168.1.1`) succeed even when the VPN is down. This is inherent to "allow LAN"
mode and is the accepted trade-off for LAN reachability. Public DNS (port 53 to
non-RFC1918 addresses) remains blocked by the terminal DROP.

## Implementation Steps (Module Architecture Pattern — Option B)

Both files are already role/feature-addition modules imported only by the roles
that need them (no `lib.mkIf` role guards). The change is a pure additive edit to
the existing rule strings in each — no new files, no new options, no conditionals.

1. `modules/network-killswitch-stateless.nix`: add the 5 `iptables -A
   vpn-kill-switch -d <range> -j ACCEPT` lines + a comment block, inside
   `networking.firewall.extraCommands`, after the ESTABLISHED/RELATED line.
2. `modules/network-killswitch-service.nix`: add the same 5 lines using the
   `${ipt}` interpolation, in `startScript`, after the ESTABLISHED/RELATED line.
3. Update the header comment in `network-killswitch-stateless.nix` (the file the
   service variant refers to for rationale) to document the LAN carve-out and its
   DNS trade-off.

`extraStopCommands` / `stopScript` need no change — they flush and delete the whole
chain.

## Dependencies

None. No new flake inputs, no new packages. `pkgs.iptables` is already used.
Context7 not applicable (no external library API).

## Configuration Changes

None to any `configuration-*.nix`. No `system.stateVersion` change. No option
surface change.

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| DNS to LAN resolver works while VPN down (minor leak-surface) | Documented in-file; inherent to "allow LAN" mode; public DNS still blocked |
| Rule ordering places ACCEPT after DROP (no-op) | Inserted immediately after ESTABLISHED/RELATED, well before the terminal DROP |
| Divergence between the two kill-switch files | Same 5 rules applied to both in this change |
| `224.0.0.0/4` also permits multicast egress generally | Multicast is link-scoped, not routable to internet; needed for discovery |
