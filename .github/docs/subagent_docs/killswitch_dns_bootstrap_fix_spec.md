---
feature: killswitch_dns_bootstrap_fix
phase: 1-spec
date: 2026-09-07
supersedes: stateless_killswitch_dns_bootstrap_spec.md (2026-07-14, never implemented)
---

# Spec: Fix VPN Kill Switch DNS Bootstrap Deadlock

## 1. Current State Analysis

### User report

User imported a PIA `.ovpn` profile on the **stateless** role (GNOME → Settings →
Network → VPN import, per `networking.networkmanager.plugins = [ pkgs.networkmanager-openvpn ]`
in `modules/desktop-common.nix:51`), entered credentials, enabled the connection, and
it failed. Live log confirms:

```
RESOLVE: Cannot resolve host address: ca-montreal.privacy.network:1198 (System error)
... Could not determine IPv4/IPv6 protocol
... Connect timer expired, disconnecting.
```

UDP 1198 (PIA's standard OpenVPN port) is already an allowed bootstrap port in the
kill switch — this is not a port or credentials problem. The hostname simply never
resolves.

### Root cause — confirmed

`modules/network-killswitch-stateless.nix` installs an always-on iptables `OUTPUT`
chain (see file header/rule-order comments). It contains an unconditional DNS guard,
added in commit `0a21f82`:

```
iptables -A vpn-kill-switch -p udp --dport 53 -j DROP
iptables -A vpn-kill-switch -p tcp --dport 53 -j DROP
```

placed *before* the LAN carve-out, specifically to stop LAN-resolver DNS from acting
as a general-purpose leak path (see `0a21f82`'s own commit message).

The stateless wired connection is the `wired-fallback` NetworkManager profile
(`modules/network.nix`, `ipv4.method = "auto"`, DHCP) — no static DNS override. So
`services.resolved` gets its per-link DNS servers from the DHCP lease: the LAN
router's IP (RFC1918). When NM-openvpn asks glibc to resolve
`ca-montreal.privacy.network`, resolved queries the router at `<router-ip>:53`. That
query is *not* a tunnel-interface packet, so it hits the guard's blanket DROP before
it ever reaches the LAN carve-out below. No DNS → no server IP → `tun0` never comes
up → kill switch correctly keeps blocking everything else. Deadlock.

### Why the July 2026 spec's fix was never sufficient (and never landed)

`.github/docs/subagent_docs/stateless_killswitch_dns_bootstrap_spec.md` proposed
allowing UDP/TCP 53 only to `1.1.1.1` / `9.9.9.9` (the same pair configured as
`services.resolved`'s `FallbackDNS` in `modules/network.nix`). Two problems:

1. **It was never implemented.** `git log -- modules/network-killswitch-stateless.nix`
   shows only `c103786`, `2ee1656`, `0a21f82` — none add these rules. The DROP rules
   from `0a21f82` are exactly what the live log confirms is still firing today.
2. **`FallbackDNS` would not have been used even if implemented.** Per
   `systemd-resolved` semantics, `FallbackDNS=` only activates when a link has *no*
   per-link DNS servers configured at all. Here DHCP supplies the router's resolver
   as a per-link server, so resolved has a server and never falls back — it keeps
   querying the router, which the firewall (correctly) drops. The old fix would have
   opened a firewall hole that resolved would never actually route traffic through.

### Confirmed mechanism for a correct fix

`networking.networkmanager.ensureProfiles.profiles` is typed as an attrs-of-INI-file
submodule (verified via NixOS option lookup: "attribute set of (open submodule of
attribute set of section of an INI file...)"). This means a *different* module than
the one declaring a profile's `connection`/`ipv4.method` keys can contribute
*additional* keys (e.g. `ipv4.dns`, `ipv4.ignore-auto-dns`) to the same named
profile (`"wired-fallback"`), and NixOS merges them per-key with no collision — as
long as no two modules set the *same* leaf key. This lets the kill switch module add
a DNS override to the profile network.nix already declares, following Option B
(the shared base file stays role-agnostic; the addition lives in the role file).

## 2. Problem Definition

The kill switch must permit exactly enough DNS resolution to bootstrap a
hostname-based VPN tunnel, and the system must actually *use* the resolver the
firewall allows — otherwise the firewall hole is inert (as the July spec's would
have been) and the deadlock persists. All other clearnet DNS must stay blocked when
no tunnel is up, preserving the leak fix from `0a21f82`.

### Requirements

1. NM-openvpn must be able to resolve the VPN server hostname while the stateless
   kill switch is active.
2. The DNS allowance stays narrow: only two fixed, non-LAN resolver IPs — no
   general port-53 opening, no re-opening the LAN-resolver leak `0a21f82` closed.
3. The system's actual DNS server list must include those same two IPs, or the
   firewall allowance is inert (this is the specific defect in the unlanded spec).
4. No change to always-on behavior on stateless; no new runtime toggle there.
5. `network-killswitch-service.nix` (desktop/htpc toggle) gets the same firewall
   rule addition, to stay structurally consistent with its own header claim of
   mirroring the stateless chain. Its NM DNS override is **out of scope** — see
   §5 Risks for why forcing fixed DNS statically would be wrong for a toggleable,
   default-off feature on roles whose per-host wired profile isn't fixed and
   uniform the way stateless's single DHCP fallback profile is.
6. No new flake inputs, no new packages.

## 3. Proposed Solution

### 3a. `modules/network.nix` — new same-module option + profile addition

Add an option this module both declares and consumes (the CLAUDE.md carve-out for
`lib.mkIf` gating by an option the same module declares):

```nix
options.vexos.network.forceFixedDns = lib.mkOption {
  type = lib.types.bool;
  default = false;
  description = ''
    Forces the wired-fallback NetworkManager profile to use fixed DNS resolvers
    (1.1.1.1, 9.9.9.9) instead of the DHCP/router-provided resolver. Enabled by
    the stateless-role VPN kill switch, whose DNS guard blocks queries to any
    LAN resolver — only these two fixed IPs are firewall-permitted for VPN
    hostname bootstrap, so the system must actually be configured to query them.
  '';
};
```

In `config`, append one more entry to the existing
`networking.networkmanager.ensureProfiles.profiles = lib.mkMerge [ ... ]` list:

```nix
(lib.mkIf config.vexos.network.forceFixedDns {
  "wired-fallback".ipv4 = {
    ignore-auto-dns = "true";
    dns             = "1.1.1.1;9.9.9.9";
  };
})
```

This adds only new INI keys to the `wired-fallback` section already declared above
in the same file — no leaf-key collision, per the confirmed option type.
`wired-static` (the optional user-configured static-IP profile) is deliberately
untouched: it is per-host, and a host that pairs a custom static DNS with the kill
switch is an edge case outside this bug's scope (documented in §5).

### 3b. `modules/network-killswitch-stateless.nix` — firewall + option wiring

- Set `vexos.network.forceFixedDns = true;` in `config`.
- Insert two ACCEPT rules for the fixed resolvers, positioned after the
  tunnel-interface ACCEPTs and *before* the blanket DNS-guard DROP (rule order is
  load-bearing, per the file's existing header):

```
# ── DNS bootstrap (fixed resolvers only) ────────────────────────────────────
# Narrow exception to the DNS guard below: NM-openvpn must resolve the VPN
# server hostname before any tunnel interface exists, so the tunnel-ACCEPT
# rules above cannot yet match. Only these two fixed, non-LAN IPs are allowed —
# never the LAN/router resolver, which is exactly the leak 0a21f82 closed.
# vexos.network.forceFixedDns (set below) points the wired-fallback profile's
# DNS at these same two IPs, so this allowance is actually exercised.
iptables -A vpn-kill-switch -p udp --dport 53 -d 1.1.1.1 -j ACCEPT
iptables -A vpn-kill-switch -p udp --dport 53 -d 9.9.9.9 -j ACCEPT
iptables -A vpn-kill-switch -p tcp --dport 53 -d 1.1.1.1 -j ACCEPT
iptables -A vpn-kill-switch -p tcp --dport 53 -d 9.9.9.9 -j ACCEPT
```

- Update the file header's DNS paragraph to describe the two-resolver exception
  (it currently reads "port 53 is allowed only out of a tunnel interface," which
  becomes inaccurate).

### 3c. `modules/network-killswitch-service.nix` — firewall mirror only

- Add the same four `${ipt}` ACCEPT lines to `startScript`, same relative position.
- Do **not** set `forceFixedDns` or any DNS override here (see Requirement 5 / §5
  Risks). Add a comment noting that on this toggleable variant, actually using
  these resolvers during bootstrap requires the host's active wired connection to
  already point at 1.1.1.1/9.9.9.9 (e.g. via `vexos.network.staticWired.dns` or a
  manual `nmcli` DNS override) — the firewall hole alone does not force it, exactly
  as demonstrated by the unlanded July spec.

## 4. Implementation Steps

1. `modules/network.nix`: add `vexos.network.forceFixedDns` option + the new
   `mkMerge` list entry under `ensureProfiles.profiles`.
2. `modules/network-killswitch-stateless.nix`: add `vexos.network.forceFixedDns = true;`,
   insert the four firewall rules, update header comment.
3. `modules/network-killswitch-service.nix`: insert the four firewall rules into
   `startScript`, add the scoping comment. No option wiring.

No changes to `configuration-stateless.nix` — import list is already correct.

## 5. Risks and Mitigations

- **Risk:** Forcing `forceFixedDns` unconditionally wherever the kill switch
  *capability* is present (rather than only stateless, where it's always-on) would
  silently change default DNS behavior on desktop/htpc machines that have never
  started the kill switch — including changing this dev machine's own networking.
  **Mitigation:** `forceFixedDns` is wired to `true` only in
  `network-killswitch-stateless.nix`, which is imported only by the stateless role
  and is itself always-on. `network-killswitch-service.nix` gets no DNS override.
- **Risk:** A host using `vexos.network.staticWired` with a custom (non-fixed) `dns`
  list, combined with the stateless kill switch, would still deadlock (the `wired-static`
  profile isn't touched by this fix). **Mitigation:** out of scope — no current
  stateless host config sets `staticWired`; documented here for future reference.
- **Risk:** `dns = "1.1.1.1;9.9.9.9"` with `ignore-auto-dns = "true"` means the
  stateless role's normal-operation DNS (not just VPN bootstrap) now goes to
  Cloudflare/Quad9 instead of the router, always. **Mitigation:** this matches the
  kill switch module's own existing documented design — its header already states
  LAN hostname resolution via the router is not relied upon (only `.local` via mDNS
  and direct IP access), so this is consistent with, not a regression of, current
  behavior.

## 6. Dependencies

None. No new flake inputs, no new nixpkgs packages. Context7 not applicable (no
external library/API surface — internal NixOS module options only).

## 7. Validation Plan

- `nix flake show --impure` — structure unchanged (no new outputs).
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd` (network.nix + service
  file touched — desktop role).
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia` — this dev host's
  own variant, to also catch any unintended eval-time regression here.
- `sudo nixos-rebuild dry-build --flake .#vexos-stateless-amd` — stateless is the
  primary target of this fix.
- `sudo nixos-rebuild dry-build --flake .#vexos-htpc-amd` — htpc also imports the
  toggleable service module.
- Runtime smoke test on the actual stateless host (not this dev machine):
  1. Kill switch active, no VPN → `nslookup ca-montreal.privacy.network` resolves.
  2. Enable the PIA connection in GNOME → `tun0` comes up, full internet via tunnel.
  3. Confirm a plain clearnet request (e.g. `curl -m3 example.com`) still fails
     while the tunnel is down — kill switch leak posture intact.
