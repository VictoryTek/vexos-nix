# Spec: Toggleable VPN Kill Switch Service (Desktop & HTPC Roles)

**Feature:** `killswitch_service`
**Date:** 2026-06-24
**Phase:** 1 — Research & Specification

---

## Current State

`modules/network-killswitch-stateless.nix` implements an always-on VPN kill switch
for the stateless role using `networking.firewall.extraCommands` (iptables). It is
imported unconditionally in `configuration-stateless.nix` and activates at firewall
init — it cannot be toggled at runtime.

Desktop and HTPC roles have no kill switch at all.

---

## Problem Definition

Desktop and HTPC users want a VPN kill switch they can toggle at runtime without
a `nixos-rebuild switch`. The always-on `extraCommands` approach is wrong for these
roles because:
- Users may occasionally browse without a VPN
- A compile-time toggle requires a rebuild for every enable/disable

The vex-vpn companion app (once updated per its own fix task) will call
`systemctl start/stop vpn-kill-switch` to drive the kill switch from its UI.

---

## Proposed Solution

**New file:** `modules/network-killswitch-service.nix`

Wraps the same iptables kill switch rules as the stateless module in a systemd
`oneshot` service with `RemainAfterExit = true`. The service is defined but inactive
by default — the user (or the vex-vpn app) starts it explicitly.

**Ordering:** `After = firewall.service` + `PartOf = firewall.service`
- `After`: correct startup ordering if both activate simultaneously
- `PartOf`: if the firewall restarts (e.g., during `nixos-rebuild switch`), the
  kill switch service is also restarted, re-applying its rules after the firewall
  reloads — prevents rules from silently disappearing after a rebuild

**Polkit rule:** grants any user in the `users` group permission to start and stop
`vpn-kill-switch.service` without a sudo password prompt.

**IPv6:** `networking.enableIPv6 = false` — user confirmed IPv6 is never used on
any role.

---

## Implementation Steps

### 1. `modules/network-killswitch-service.nix` (new)
- Declare `networking.enableIPv6 = false`
- Define `systemd.services.vpn-kill-switch` with iptables start/stop scripts using
  absolute `pkgs.iptables` paths (avoids PATH dependency in service context)
- Service: `Type = oneshot`, `RemainAfterExit = true`, not wantedBy anything
- Add `security.polkit.extraConfig` rule for `vpn-kill-switch.service` start/stop

### 2. `configuration-desktop.nix`
- Add `./modules/network-killswitch-service.nix` to imports

### 3. `configuration-htpc.nix`
- Add `./modules/network-killswitch-service.nix` to imports

### 4. `justfile`
- Add `enable-kill-switch` recipe: guards on stateless variant, then
  `systemctl start vpn-kill-switch.service`
- Add `disable-kill-switch` recipe: guards on stateless variant, then
  `systemctl stop vpn-kill-switch.service`
- Insert before the `rebuild` recipe

---

## Iptables Rules (identical to stateless module)

- Loopback: ACCEPT
- ESTABLISHED/RELATED: ACCEPT (in-flight transfers survive reconnect)
- DHCP outbound: ACCEPT
- VPN bootstrap ports: UDP 1194, TCP 443, UDP 1197/1198, TCP 501/502, UDP 51820, UDP 41641
- Tunnel interfaces: `tun+`, `wg+`, `nordlynx`, `tailscale0`
- Everything else: DROP on OUTPUT chain

---

## Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| Firewall restart clears rules while service reports active | `PartOf = firewall.service` causes service restart alongside firewall restart |
| iptables `-D`/`-F`/`-X` in stop script fail if chain already gone | All stop commands guarded with `2>/dev/null \|\| true` |
| Polkit rule too broad | Scoped to exact unit name and only `start`/`stop` verbs |
| `security.polkit.extraConfig` conflicts with other polkit rules | addRule is additive; no conflict with existing polkit config |

---

## Files Changed

- `modules/network-killswitch-service.nix` — new
- `configuration-desktop.nix` — add import
- `configuration-htpc.nix` — add import
- `justfile` — add two recipes
