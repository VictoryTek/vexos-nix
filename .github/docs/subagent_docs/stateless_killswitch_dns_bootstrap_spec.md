# Spec: Kill Switch DNS Bootstrap Fix (stateless + toggleable)

**Feature:** `stateless_killswitch_dns_bootstrap`
**Date:** 2026-07-14
**Status:** Phase 1 Complete

---

## 1. Current State Analysis

### What the user reported

> "The stateless kill switch is designed to disable the GNOME NetworkManager. That
> cannot be the design — I need NM to bring up the OpenVPN connection. With the kill
> switch on and no VPN, I have no internet and no way to connect the VPN."

### What is actually true

NetworkManager is **never disabled** anywhere in the repo:

| Location | Fact |
|----------|------|
| `modules/network.nix:45` | `networking.networkmanager.enable = true` (unconditional, all roles) |
| `modules/gnome.nix:270` | `networking.networkmanager.packages = [ pkgs.networkmanager-openvpn ]` |
| repo-wide grep | No `networkmanager.enable = false`, no `systemctl stop/mask NetworkManager`, no masking unit anywhere |

The "disables NetworkManager" description is a **symptom misdiagnosis** from the prior
investigation. NM is running the whole time; it simply cannot reach anything useful
because the kill switch blocks the one thing NM-openvpn needs to bootstrap a tunnel: DNS.

### Root cause — DNS bootstrap deadlock

`modules/network-killswitch-stateless.nix` installs an always-on iptables `OUTPUT`
chain that ACCEPTs only: loopback, ESTABLISHED/RELATED, DHCP, the VPN bootstrap
ports (UDP 1194/1197/1198/51820/41641, TCP 443/501/502), and the tunnel interfaces
(`tun+`, `wg+`, `nordlynx`, `tailscale0`) — then DROPs everything else.

**Port 53 (DNS) is intentionally not on the allow list** (see the file header, lines
28–31: "DNS is port 53 — not on any allow list … hits the DROP rule and fails, which
is correct kill switch behaviour").

PIA (and every other commercial) `.ovpn` profile connects to a **hostname**
(e.g. `us-east.privateinternetaccess.com`), not a bare IP. So the connect sequence is:

1. User selects the PIA profile in GNOME → NM-openvpn starts.
2. NM-openvpn must resolve the server hostname → UDP/TCP 53 query.
3. Kill switch **DROPs** the query (port 53 not allowed).
4. Hostname never resolves → OpenVPN never reaches the server → `tun0` never comes up.
5. No tunnel → kill switch keeps dropping all clearnet → **no internet, no VPN**.

This is a chicken-and-egg deadlock: DNS is needed to bring the tunnel up, but the kill
switch blocks DNS until the tunnel is up. The bootstrap *port* allowances (1198, etc.)
are useless because the client cannot learn the server's IP in the first place.

### Scope: the same latent bug exists in the toggleable variant

`modules/network-killswitch-service.nix` (desktop + htpc roles) wraps the **same**
chain rules in a start/stop systemd oneshot. Its header explicitly states it "Wraps
the same iptables OUTPUT chain rules as network-killswitch-stateless.nix." It has the
identical missing-DNS deadlock: once enabled, if the tunnel drops and NM must
re-resolve the server hostname to reconnect, it cannot. The two files are designed to
mirror each other, so the fix must be applied to both to keep them consistent and to
avoid leaving a known deadlock in the desktop/htpc path.

---

## 2. Problem Definition

The always-on kill switch makes it **impossible to establish or re-establish** a
hostname-based OpenVPN/WireGuard tunnel, because DNS resolution of the VPN endpoint is
blocked. The kill switch must permit the minimum DNS egress required to resolve the VPN
server hostname, without opening a general clearnet DNS leak.

### Requirements

1. NM-openvpn MUST be able to resolve the VPN server hostname while the kill switch is active.
2. The DNS allowance MUST be as narrow as possible — only to trusted, fixed resolvers.
3. All other clearnet egress MUST remain blocked when no tunnel is active (kill switch intact).
4. No change to the always-on guarantee on stateless; no new runtime toggle on stateless.
5. The toggleable desktop/htpc variant MUST receive the identical fix to stay consistent.
6. No new flake inputs, no new packages.

---

## 3. Proposed Solution (Option A — user-selected)

Allow port 53 egress **only to the two resolvers `services.resolved` is already
configured to use** as `FallbackDNS` in `modules/network.nix:206`:
`1.1.1.1` (Cloudflare) and `9.9.9.9` (Quad9). Both UDP and TCP 53 (DNS-over-TCP
fallback for large responses / truncation).

### Rules added (inserted in the bootstrap section, before the final DROP)

```
# DNS bootstrap — allow hostname resolution of the VPN endpoint ONLY to the fixed
# resolvers configured as services.resolved FallbackDNS in network.nix. Without this,
# NM-openvpn cannot resolve the VPN server hostname and the tunnel can never bootstrap.
# Narrowest viable leak surface: these two resolvers see which VPN hostnames are
# looked up, nothing more. All other clearnet egress stays blocked.
iptables -A vpn-kill-switch -p udp --dport 53 -d 1.1.1.1 -j ACCEPT
iptables -A vpn-kill-switch -p udp --dport 53 -d 9.9.9.9 -j ACCEPT
iptables -A vpn-kill-switch -p tcp --dport 53 -d 1.1.1.1 -j ACCEPT
iptables -A vpn-kill-switch -p tcp --dport 53 -d 9.9.9.9 -j ACCEPT
```

### Why this is safe

- **Narrow:** only two destination IPs, only port 53. No general DNS egress.
- **Consistent with existing config:** identical to the resolvers `resolved` already
  falls back to, so no new trust is introduced beyond what the system already uses.
- **Leak posture unchanged for real traffic:** once the tunnel is up, `resolved` uses
  the VPN-pushed DNS through `tun+`; these two static allows are only exercised during
  bootstrap. Everything except port-53-to-two-IPs remains DROPped when the VPN is down.
- **No IP-pinning fragility:** hostnames and region-switching keep working unchanged.

### Ordering

The four rules are appended in the existing bootstrap block (after the DHCP rule,
alongside the other `--dport` allowances) and therefore precede the terminal
`-j DROP`. iptables evaluates the chain top-to-bottom; first match wins, so placement
before DROP is required and satisfied.

---

## 4. Implementation Steps

Follows Module Architecture Pattern (Option B): no new `lib.mkIf` role guards; this is
a content edit to two existing sibling modules that already carry the kill switch rules.

### Step 1 — `modules/network-killswitch-stateless.nix`

- Add the four DNS-bootstrap `iptables` ACCEPT lines inside
  `networking.firewall.extraCommands`, in the "VPN bootstrap ports" block, immediately
  after the DHCP allow (line 55) and before the tunnel-interface block.
- Update the file header DNS note (lines 28–31) to reflect that DNS to the two fixed
  resolvers is now permitted for endpoint resolution, and why (bootstrap deadlock).

### Step 2 — `modules/network-killswitch-service.nix`

- Add the identical four rules to `startScript` (the `pkgs.writeShellScript` block),
  in the same relative position (after the DHCP allow on line 30), using the `${ipt}`
  interpolation style already used in that file.
- Keep the two files' chains byte-for-byte equivalent (modulo the `${ipt}` vs literal
  `iptables` invocation style already differing between them).

### Step 3 — No change to `configuration-stateless.nix`

The import list and role wiring are already correct; only the chain contents change.

---

## 5. Files Modified

| File | Action | Reason |
|------|--------|--------|
| `modules/network-killswitch-stateless.nix` | Edit | Add DNS bootstrap allow to fixed resolvers; update header note |
| `modules/network-killswitch-service.nix` | Edit | Same fix, keep toggleable variant consistent |

---

## 6. Dependencies

None. No new flake inputs, no new nixpkgs packages. `pkgs.iptables` already used by
both files. Context7 not applicable (no external library/API surface).

---

## 7. Validation Plan

This dev host is Windows/MSYS with **no Nix toolchain**; the Linux-only build steps
below MUST be run on the NixOS target host or CI, not here.

- `nix flake show --impure` — structure unchanged (no new outputs).
- `sudo nixos-rebuild dry-build --flake .#vexos-stateless-amd` — stateless closure.
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd` and
  `.#vexos-htpc-amd` — toggleable-variant roles (service file touched).
- Runtime smoke test on the stateless host:
  1. Boot with kill switch active, no VPN → confirm `nslookup us-east.privateinternetaccess.com`
     resolves (DNS to 1.1.1.1/9.9.9.9 now allowed) but a clearnet HTTP fetch still fails.
  2. Connect the PIA profile in GNOME → tunnel comes up, full internet through `tun0`.
- `bash scripts/preflight.sh` — full pre-push gate.
- `git ls-files hardware-configuration.nix` → empty.
- `system.stateVersion` unchanged in all `configuration-*.nix`.

---

## 8. Risks and Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| DNS query to a resolver other than 1.1.1.1/9.9.9.9 still blocked | LOW | `resolved` FallbackDNS is exactly these two; matches system config. If a host overrides DNS, update both lists together. |
| Minor DNS metadata leak to Cloudflare/Quad9 during bootstrap | LOW (accepted) | Narrowest option chosen; only two IPs, only port 53. All other clearnet still dropped. |
| Rules land after the DROP and never match | LOW | Appended in the bootstrap block, before the terminal DROP; verified by rule ordering. |
| Desktop/htpc toggle drifts from stateless again | LOW | Both files updated in the same change; mirror invariant restored. |
