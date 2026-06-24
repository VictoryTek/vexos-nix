# Spec: VPN Kill Switch for Stateless Role

**Feature:** `stateless_vpn_killswitch`
**Date:** 2026-06-24
**Status:** Phase 1 Complete

---

## 1. Current State Analysis

### Relevant Existing Modules

| File | Relevance |
|------|-----------|
| `configuration-stateless.nix` | Stateless role entrypoint; imports list |
| `modules/network.nix` | Firewall baseline (`networking.firewall.enable = true`); uses iptables `extraCommands`; Tailscale; systemd-resolved |
| `modules/network-desktop.nix` | SMB/NFS/WSD discovery; uses `networking.firewall.extraCommands` with iptables raw table |
| `modules/gnome.nix:254` | Declares `networking.networkmanager.plugins = [ pkgs.networkmanager-openvpn ]` |
| `modules/impermanence.nix` | `/etc/NetworkManager/system-connections` is intentionally omitted from persistence (line 197-200); `extraPersistDirs` option exists for additions |

### Firewall Backend

The project uses the **iptables-based NixOS firewall** (default). `networking.nftables.enable` is not set anywhere. `network-desktop.nix` already uses `networking.firewall.extraCommands` with iptables syntax. The kill switch must use the same backend to avoid a conflict.

### OpenVPN Plugin Status on 25.11

A confirmed regression in NixOS 25.11 causes the OpenVPN D-Bus service (`org.freedesktop.NetworkManager.openvpn`) not to register when the plugin is declared via `networking.networkmanager.plugins`. The fix is to use `networking.networkmanager.packages` instead. This must be corrected in `gnome.nix` as a prerequisite — without it, NM cannot import or activate `.ovpn` files on 25.11.

**Reference:** https://discourse.nixos.org/t/openvpn-support-missing-in-networkmanager-on-25-11/72860

---

## 2. Problem Definition

The stateless role has no traffic leak protection. If a user connects to PIA VPN and the tunnel drops (crash, sleep/wake, server rotation), traffic resumes over the clearnet interface without warning. All subsequent traffic — including Tor Browser bootstrap connections — leaks the user's real IP.

Additionally, VPN connection profiles are not persisted across reboots on the stateless role, requiring re-import and re-authentication every session.

### Requirements

1. All clearnet egress MUST be blocked when no VPN tunnel is active
2. VPN region switching MUST be possible without reconfiguring the system
3. Credentials MUST NOT be stored declaratively in the Nix store or git
4. Tor Browser traffic MUST be covered by the kill switch automatically
5. A future custom VPN GUI app using PIA's `.ovpn` files MUST work without changes to the kill switch
6. IPv6 traffic MUST NOT leak (PIA OpenVPN does not tunnel IPv6)
7. VPN profiles MUST survive reboots on the stateless role

---

## 3. Architecture Decision: `pkgs.private-internet-access-vpn`

**Finding:** No `pkgs.private-internet-access-vpn` exists in official nixpkgs. PIA distributes only a `.run` installer for Linux that unpacks to `/opt/piavpn` — incompatible with NixOS's non-FHS filesystem without significant wrapping.

**Third-party NixOS PIA modules found:**
- `Fuwn/pia.nix` (GitHub) — supports WireGuard + OpenVPN; `services.pia` interface; `authUserPassFile` for sops-nix credentials
- `rcambrj/nix-pia-vpn` (GitHub) — WireGuard via networkd only
- `mrehanabbasi/pia.nix` (GitHub) — fork of above

**Decision:** Do NOT add a third-party flake dependency. The trust surface and maintenance risk of an unofficial module running with root network privileges outweighs the benefit. The NetworkManager + nftables path requires zero new dependencies and is fully auditable.

---

## 4. Proposed Solution Architecture

### Separation of Concerns

```
┌─────────────────────────────────┐
│  VPN MANAGEMENT (user-facing)   │
│  NetworkManager + GNOME UI      │
│  • Import .ovpn files via GUI   │
│  • Switch regions by selecting  │
│    a different VPN connection   │
│  • Credentials entered via      │
│    GNOME VPN dialog (not in git)│
│  • Profiles persisted to        │
│    /persistent (NM system-conn) │
└───────────────┬─────────────────┘
                │ creates tun0 / tun1...
                ▼
┌─────────────────────────────────┐
│  KILL SWITCH (kernel-enforced)  │
│  iptables OUTPUT chain          │
│  • Allows: lo, DHCP, PIA ports  │
│  • Allows: tun+ AND wg+         │
│  • DROPs: all other egress      │
│  • Completely agnostic to which │
│    app manages the VPN          │
└─────────────────────────────────┘
```

### Why tun+ AND wg+

The kill switch allows all `tun+` (OpenVPN) and `wg+` (WireGuard) interfaces. This ensures:
- Current: NM-managed OpenVPN via `.ovpn` files → `tun0` → covered
- Future: custom GUI app using `.ovpn` files → `tun0` → covered (no changes needed)
- Future: WireGuard-based approach → `wg0` → covered

### IPv6 Leak Prevention

PIA's OpenVPN does not tunnel IPv6. `networking.enableIPv6 = false` on the stateless role eliminates the IPv6 leak surface entirely. This is stateless-only so it does not affect other roles.

### DNS Leak Prevention

PIA's `.ovpn` files include `dhcp-option DNS <pia-dns-ip>` directives. The `networkmanager-openvpn` plugin reads these and updates `systemd-resolved` when the tunnel connects. When the tunnel is down, external DNS servers (including resolved's FallbackDNS) are unreachable because the kill switch blocks all non-VPN clearnet egress — so DNS also stops, which is the correct kill switch behavior.

---

## 5. PIA OpenVPN Ports (Kill Switch Allowlist)

From PIA support documentation:

| Protocol | Port | Encryption |
|----------|------|------------|
| UDP | 1198 | AES-128-CBC + SHA1 (standard, default) |
| UDP | 1197 | AES-256-CBC + SHA256 (strong) |
| TCP | 502  | AES-128-CBC + SHA1 (standard TCP) |
| TCP | 501  | AES-256-CBC + SHA256 (strong TCP) |

All four ports must be permitted for any destination IP so region switching works without modifying the kill switch.

---

## 6. Implementation Steps

### Step 1 — Fix NM OpenVPN plugin declaration in `modules/gnome.nix`

**Change:** Line 254: `networking.networkmanager.plugins` → `networking.networkmanager.packages`

```nix
# Before (broken on 25.11):
networking.networkmanager.plugins = [ pkgs.networkmanager-openvpn ];

# After (correct on 25.11):
networking.networkmanager.packages = [ pkgs.networkmanager-openvpn ];
```

This is imported by desktop, stateless, htpc, server roles — the fix is safe for all of them.

### Step 2 — Create `modules/network-killswitch-stateless.nix` (new file)

Responsibilities:
- Disable IPv6 (`networking.enableIPv6 = false`)
- Declare iptables OUTPUT kill switch chain via `networking.firewall.extraCommands`
- Declare cleanup via `networking.firewall.extraStopCommands`

Kill switch chain logic:
1. Create chain `vpn-kill-switch` (idempotent: create or flush)
2. Accept loopback (`-o lo`)
3. Accept established/related connections (`-m conntrack --ctstate ESTABLISHED,RELATED`)
4. Accept DHCP (`-p udp --sport 68 --dport 67`)
5. Accept PIA OpenVPN bootstrap: UDP 1197, UDP 1198, TCP 501, TCP 502 (any destination)
6. Accept all traffic on `tun+` (OpenVPN)
7. Accept all traffic on `wg+` (WireGuard — future-proofing)
8. DROP everything else
9. Add jump from OUTPUT to chain (idempotent: check before insert)

Stop commands remove the jump rule, flush the chain, and delete it.

### Step 3 — Update `configuration-stateless.nix`

Two additions:
1. Import `./modules/network-killswitch-stateless.nix`
2. Add `vexos.impermanence.extraPersistDirs = [ "/etc/NetworkManager/system-connections" ]`

Using `extraPersistDirs` (not editing impermanence.nix directly) is the correct Module Architecture pattern — it's an addition to the stateless role's config, not a change to the module defaults.

---

## 7. Files Modified

| File | Action | Reason |
|------|--------|--------|
| `modules/gnome.nix` | Edit line 254 | Fix NM OpenVPN plugin broken on 25.11 |
| `modules/network-killswitch-stateless.nix` | Create | Kill switch + IPv6 disable |
| `configuration-stateless.nix` | Edit | Import kill switch; persist NM VPN profiles |

---

## 8. Dependencies

No new flake inputs. No new nixpkgs packages beyond what is already imported. All packages used (`pkgs.networkmanager-openvpn`) are already in the dependency graph.

---

## 9. User Workflow After Implementation

**First time per region:**
1. Download `.ovpn` file from PIA portal for desired region
2. GNOME Settings → Network → VPN → `+` → Import from file
3. Enter PIA OpenVPN credentials (from PIA portal → "Generate Password")
4. Connect → kill switch is active from that point

**After reboot:**
- VPN profiles and credentials are in `/persistent/etc/NetworkManager/system-connections/`
- Open GNOME Network settings, select profile, click Connect
- Kill switch was active at boot; only VPN bootstrap ports were open until connection

**Region switching:**
- Import multiple `.ovpn` files (each region = one NM profile)
- Disconnect current, select new region, connect

---

## 10. Risks and Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| NM OpenVPN plugin still broken after `.packages` fix | HIGH | Phase 3 dry-build + verification noted for Phase 3 review |
| Duplicate iptables rules on `nixos-rebuild switch` | MEDIUM | Idempotent chain create/flush + `-C` check before INSERT |
| Kill switch blocks tailscale0 traffic | LOW | Tailscale uses `tailscale0` which is not `tun+` or `wg+`. Tailscale traffic goes via `tailscale0`. Kill switch rules are OUTPUT-based and Tailscale's UDP goes through the physical interface. This needs evaluation in Phase 3. |
| DHCP fails on boot before VPN connected | LOW | DHCP allow rule (sport 68 dport 67) in kill switch handles this |
| IPv6 disable breaks LAN features | LOW | Stateless role is personal/ephemeral; no LAN services depend on IPv6 |
| Custom GUI app uses different tun device name | LOW | `tun+` wildcard matches any `tunN` interface |

### Tailscale Interaction Note

Tailscale is enabled in `network.nix` (imported by stateless). Tailscale uses WireGuard internally and creates a `tailscale0` interface. The kill switch allows `wg+` — but Tailscale uses `tailscale0`, not `wg0`. Physical interface traffic for Tailscale's UDP 41641 handshake would be blocked by the kill switch DROP rule.

**Resolution options (to evaluate in Phase 3):**
- Option A: Add `iptables -A vpn-kill-switch -p udp --dport 41641 -j ACCEPT` to allow Tailscale bootstrap alongside PIA
- Option B: Accept `tailscale0` explicitly: `iptables -A vpn-kill-switch -o tailscale0 -j ACCEPT`
- Option C: Add both — allows Tailscale to function independently of PIA VPN

Given the stateless role's privacy focus, Option B+C (allow Tailscale interface + its bootstrap port) is recommended so both PIA and Tailscale function simultaneously.
