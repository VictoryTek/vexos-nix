# SMB Auto-Discovery in GNOME Files (Nautilus) — Research & Specification

## Feature Name
`smb_autodiscovery`

## Date
2026-05-01

---

## 1. Current State Analysis

### 1.1 Symptom

In GNOME Files (Nautilus) → **Other Locations** / **Network** sidebar entry, the user's NAS device does not appear. SMB auto-discovery is not working despite extensive prior configuration work.

### 1.2 What is already configured (current `main`)

Four prior attempts have been made. The current codebase includes all of the following:

**`modules/network.nix`** (universal base, all roles):
- `services.avahi.enable = true`
- `services.avahi.nssmdns4 = true` (mDNS `.local` resolution via NSS)
- `services.avahi.openFirewall = true` (UDP 5353)
- `services.resolved.enable = true` (systemd-resolved)
- `services.resolved.dnssec = "allow-downgrade"`
- `services.resolved.fallbackDns = [ "1.1.1.1" "9.9.9.9" ]`
- `cifs-utils` installed
- Firewall enabled
- SSH, Tailscale enabled

**`modules/network-desktop.nix`** (imported by desktop, htpc, server, stateless — NOT headless):
- `services.samba.enable = true` (client-only; all daemons disabled via `lib.mkDefault false`)
- `smb.conf` generated with `workgroup = "WORKGROUP"`, `client min/max protocol = SMB2/SMB3`
- `services.avahi.publish = { enable = true; addresses = true; workstation = true; userServices = true; }`
- `services.samba-wsdd = { enable = true; openFirewall = true; discovery = true; }`
- `systemd.tmpfiles.settings."10-samba-etc"` symlinks `/etc/samba` → `/etc/static/samba`
- `boot.supportedFilesystems = [ "nfs" ]`

**`modules/gnome.nix`** (GNOME roles):
- `services.desktopManager.gnome.enable = true` → implicitly sets `services.gvfs.enable = true`
- Nautilus overlaid to nixpkgs-unstable
- gvfs is NOT overlaid (remains on stable channel)

### 1.3 Prior fix attempts and their outcomes

| # | Commit / Spec | What was done | Outcome |
|---|---|---|---|
| v1 | `bec7bec` | Added Avahi publish, WSDD (responder-only), NFS support, samba pkg | WSDD responder-only — no discovery. No smb.conf generated. |
| v2 | `da6e40c` | Added `services.samba.enable = true` (client-only) for smb.conf | smb.conf fixed, but WSDD still responder-only. gvfsd-smb-browse workgroup browsing empty. |
| v3 | `3082227` | Added tmpfiles rule for `/etc/samba` symlink | Fixed activation race. WSDD still responder-only. |
| v4 | `smb_nfs_discovery_spec.md` | Added `discovery = true` to WSDD, `addresses/workstation` to Avahi publish | WSDD discovery socket created. **NAS still does not appear.** |

### 1.4 What the previous spec got right

The v4 spec correctly identified that WSDD discovery mode was needed for hosts advertising via WS-Discovery (primarily Windows 10/11 and Samba servers running wsdd). The WSDD fix is confirmed correct and should remain.

### 1.5 What the previous spec missed

The v4 spec assumed all NAS devices advertise via WS-Discovery. **Most consumer NAS devices (Synology, QNAP, TrueNAS, Unraid, etc.) advertise via mDNS/Bonjour** (`_smb._tcp` service type), NOT via WS-Discovery. WSD is primarily a Windows protocol.

For the NAS to appear in Nautilus, the discovery chain is:
1. NAS advertises `_smb._tcp` via mDNS multicast on UDP 5353
2. Avahi daemon receives the multicast advertisement
3. `gvfsd-dnssd` queries Avahi for discovered `_smb._tcp` services
4. `gvfsd-network` aggregates results from gvfsd-dnssd, gvfsd-wsdd, gvfsd-smb-browse
5. Nautilus displays them in the Network view

**The critical gap**: Both `services.avahi` and `services.resolved` are enabled. systemd-resolved has a built-in mDNS responder/resolver. When both run simultaneously:
- systemd-resolved binds its mDNS handler on all network interfaces
- Avahi also tries to handle mDNS on the same interfaces
- The two services conflict, causing mDNS service browsing to fail silently
- Avahi's service browser never receives NAS advertisements
- gvfsd-dnssd has no services to report → Network view stays empty

This is a [well-documented conflict](https://wiki.archlinux.org/title/Avahi#Installation) — the Arch Wiki explicitly warns: *"systemd-resolved has a built-in mDNS service, make sure to disable systemd-resolved's multicast DNS resolver/responder or disable systemd-resolved.service entirely before using Avahi."*

---

## 2. Root Cause

**systemd-resolved's MulticastDNS handler conflicts with Avahi's mDNS service browsing.**

The current configuration has `services.resolved.enable = true` without explicitly disabling resolved's built-in MulticastDNS support. In systemd v256+ (as shipped in NixOS 25.05/25.11), the default `MulticastDNS=` setting in `resolved.conf` is `yes`, meaning resolved actively participates in mDNS — conflicting with the Avahi daemon that is also enabled.

### Why WSDD discovery alone didn't fix it

WSDD discovery (`gvfsd-wsdd`) only discovers hosts that advertise via the WS-Discovery protocol (UDP 3702). This is primarily:
- Windows 10/11 with network discovery enabled
- Samba servers running wsdd/wsdd2

Most consumer NAS devices (Synology DSM, QNAP QTS, TrueNAS, Unraid, OpenMediaVault) advertise via **mDNS/Bonjour** (`_smb._tcp._tcp`), NOT WS-Discovery. To discover these, `gvfsd-dnssd` must be able to read from Avahi's service browser, which requires Avahi to be the sole mDNS handler.

### Secondary contributor: Missing NetBIOS conntrack helper

For traditional SMB browsing (gvfsd-smb-browse using libsmbclient), the client sends NetBIOS name service requests on UDP 137. With the NixOS firewall (iptables), reply packets from different source IPs are not recognized as related to the outbound request, so they are dropped. The Arch Wiki documents this as: *"Browsing network fails with 'Failed to retrieve share list from server'"* and recommends adding a conntrack helper rule.

---

## 3. Proposed Solution

Two changes to existing files. **No new files.** **No new flake inputs.** **No `lib.mkIf` guards.** Strict adherence to the project's Option B module pattern.

### 3.1 Changes

| File | Change | Reason |
|---|---|---|
| `modules/network.nix` | Add `services.resolved.extraConfig` to disable `MulticastDNS` and `LLMNR` in systemd-resolved | **Primary fix.** Prevents resolved from competing with Avahi for mDNS traffic. Avahi becomes the sole mDNS handler, allowing gvfsd-dnssd to discover NAS devices advertising `_smb._tcp`. |
| `modules/network-desktop.nix` | Add `networking.firewall.extraCommands` for NetBIOS conntrack helper | **Secondary fix.** Allows the firewall to track NetBIOS name resolution responses for traditional SMB browsing via gvfsd-smb-browse. |

### 3.2 Placement rationale

- **`modules/network.nix`** for the resolved fix: This is the universal base module where both Avahi and resolved are configured. ALL roles use both services, so the conflict affects ALL roles. The fix belongs here — not in a GNOME-specific or display-specific module — because hostname resolution via mDNS (`.local`) is also broken for headless roles when both services conflict.

- **`modules/network-desktop.nix`** for the conntrack helper: This only applies to roles that do SMB network browsing (display roles with GNOME/Nautilus). Headless roles don't browse SMB shares via a GUI, so the rule is unnecessary there.

### 3.3 Concrete file edits

#### File: `modules/network.nix`

Add after the existing `services.resolved` block:

```nix
  # ── DNS resolver ──────────────────────────────────────────────────────────
  services.resolved = {
    enable      = true;
    dnssec      = "allow-downgrade";
    fallbackDns = [ "1.1.1.1" "9.9.9.9" ];
    # Disable resolved's built-in mDNS and LLMNR handlers so they don't
    # conflict with Avahi.  Without this, resolved and Avahi race on mDNS
    # multicast traffic (UDP 5353), causing Avahi's service browser to miss
    # NAS devices advertising _smb._tcp — the root cause of SMB shares not
    # appearing in Nautilus → Network.
    # Reference: https://wiki.archlinux.org/title/Avahi#Installation
    extraConfig = ''
      MulticastDNS=no
      LLMNR=no
    '';
  };
```

#### File: `modules/network-desktop.nix`

Add after the NFS client support block:

```nix
  # ── NetBIOS conntrack helper ────────────────────────────────────────────
  # Traditional SMB browsing (gvfsd-smb-browse / libsmbclient) sends
  # broadcast queries on UDP 137.  Replies arrive from different source IPs
  # than the broadcast destination, so the firewall's conntrack doesn't
  # recognise them as RELATED — they're silently dropped.  This rule loads
  # the netbios-ns conntrack helper so replies are correctly tracked.
  # Reference: https://wiki.archlinux.org/title/Samba#%22Browsing%22_network_fails_with_%22Failed_to_retrieve_share_list_from_server%22
  networking.firewall.extraCommands = ''
    iptables -t raw -A OUTPUT -p udp -m udp --dport 137 -j CT --helper netbios-ns
  '';
```

### 3.4 Files modified

1. `modules/network.nix` — add `extraConfig` to `services.resolved` block
2. `modules/network-desktop.nix` — add `networking.firewall.extraCommands` for NetBIOS conntrack

### 3.5 Files NOT modified (deliberately)

- `modules/gnome.nix`, `modules/gnome-*.nix` — GVfs is auto-enabled by GNOME; no changes needed
- `configuration-*.nix` — no import changes needed; all roles already import the modified modules
- `flake.nix` — no new inputs
- `modules/network-desktop.nix` existing WSDD/Avahi/Samba blocks — these are correct and should remain unchanged

---

## 4. Architecture Compliance (Option B)

- ✅ Changes in existing modules only (`network.nix` base, `network-desktop.nix` addition)
- ✅ No `lib.mkIf` guards added
- ✅ No new module files created
- ✅ The resolved fix in `network.nix` applies to ALL roles (correct — the conflict affects all roles using both Avahi and resolved)
- ✅ The conntrack helper in `network-desktop.nix` applies only to display roles (correct — only they browse SMB)
- ✅ Headless-server does not import `network-desktop.nix` — no GUI browsing there
- ✅ `system.stateVersion` untouched
- ✅ `hardware-configuration.nix` untouched

---

## 5. Affected Roles

| Role | `network.nix` (resolved fix) | `network-desktop.nix` (conntrack) |
|---|---|---|
| desktop | ✅ | ✅ |
| htpc | ✅ | ✅ |
| server | ✅ | ✅ |
| stateless | ✅ | ✅ |
| headless-server | ✅ | ❌ (doesn't import) |

---

## 6. Dependencies

No new flake inputs. No new packages. The fix uses existing NixOS module options:

| Option | NixOS module | Purpose |
|---|---|---|
| `services.resolved.extraConfig` | `nixos/modules/system/boot/resolved.nix` | Passes raw config lines to `/etc/systemd/resolved.conf` |
| `networking.firewall.extraCommands` | `nixos/modules/services/networking/firewall.nix` | Appends iptables rules to the firewall script |

No new firewall ports opened. The resolved change only disables built-in mDNS/LLMNR in resolved — Avahi continues to handle mDNS on UDP 5353 as before.

---

## 7. How the Three Discovery Mechanisms Work After This Fix

### 7.1 mDNS / DNS-SD via Avahi → gvfsd-dnssd (PRIMARY for NAS devices)

**Chain**: NAS advertises `_smb._tcp` → mDNS multicast (UDP 5353) → **Avahi daemon** (sole handler, no resolved conflict) → gvfsd-dnssd queries Avahi D-Bus API → gvfsd-network → Nautilus

**Discovers**: Synology, QNAP, TrueNAS, macOS, any device running Avahi/Bonjour with SMB

### 7.2 WS-Discovery via wsdd → gvfsd-wsdd

**Chain**: Windows/Samba host responds to WSD Probe → wsdd daemon (discovery mode) → `/run/wsdd/wsdd.sock` → gvfsd-wsdd → gvfsd-network → Nautilus

**Discovers**: Windows 10/11, Samba servers running wsdd

### 7.3 Traditional SMB browsing via libsmbclient → gvfsd-smb-browse

**Chain**: libsmbclient reads smb.conf → sends NetBIOS browse requests (UDP 137) → browse-master responds → **conntrack helper tracks reply** → gvfsd-smb-browse → gvfsd-network → Nautilus

**Discovers**: Legacy Windows (pre-10) with NetBIOS enabled, old SMB1 devices. Unreliable on modern LANs.

---

## 8. Post-rebuild Testing Steps

After `sudo nixos-rebuild switch --flake .#vexos-desktop-amd` (or user's variant):

1. **Verify resolved no longer handles mDNS**:
   ```bash
   resolvectl status | grep -i multicast
   ```
   Expect: `MulticastDNS setting: no` (per interface and globally)

2. **Verify Avahi is running and browsing**:
   ```bash
   systemctl status avahi-daemon
   avahi-browse -a -t -r | grep -E '_smb|_nfs|_workstation'
   ```
   Expect: NAS devices advertising `_smb._tcp` should appear in avahi-browse output.

3. **Verify WSDD is in discovery mode** (unchanged from prior fix):
   ```bash
   systemctl status samba-wsdd
   ls -l /run/wsdd/wsdd.sock
   ```

4. **Verify conntrack helper is loaded**:
   ```bash
   sudo iptables -t raw -L OUTPUT -n | grep netbios
   ```
   Expect: A rule with `helper netbios-ns`

5. **Test Nautilus**:
   ```bash
   # Restart gvfs to pick up changes
   systemctl --user restart gvfs-daemon
   # Open Nautilus → Other Locations → Network
   nautilus network:///
   ```
   NAS devices should now appear.

6. **Manual SMB access** (always works regardless of discovery):
   - `Ctrl+L` → `smb://<nas-ip>/` or `smb://<nas-hostname>.local/`

---

## 9. Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Disabling resolved mDNS breaks `.local` hostname resolution | None | N/A | Avahi + nssmdns4 handles `.local` resolution. This is the recommended configuration per Arch Wiki and NixOS wiki. |
| Disabling LLMNR breaks name resolution for Windows hosts | Very low | Low | LLMNR is a fallback protocol; DNS and mDNS are primary. Windows 10+ prefers DNS over LLMNR. |
| NetBIOS conntrack helper increases kernel attack surface | Very low | Very low | The `nf_conntrack_netbios_ns` helper is a standard kernel module. Widely used. Only processes outbound UDP 137 packets. |
| `networking.firewall.extraCommands` conflicts with nftables | Low | Medium | NixOS defaults to iptables. If the user switches to nftables, the rule needs conversion. Current project has no nftables config. |
| Future NixOS adds `services.resolved.mdns` option, making `extraConfig` redundant | Medium | None | `extraConfig` values are additive; a future option would override cleanly. No breakage. |
| Build failure | Very low | Medium | Both `extraConfig` and `extraCommands` are string options — no eval pitfalls. Validate with `nix flake check` and `nixos-rebuild dry-build`. |
| Avahi hostname incrementing bug (known upstream issue) | Low | Low | Avahi occasionally appends `-2`, `-3` to hostnames. This is an upstream bug independent of this fix. Disabling resolved mDNS actually reduces the likelihood by eliminating the hostname race. |

---

## 10. Research Sources

1. **Arch Wiki — Avahi § Installation**: *"systemd-resolved has a built-in mDNS service, make sure to disable systemd-resolved's multicast DNS resolver/responder or disable systemd-resolved.service entirely before using Avahi."* — Documents the exact Avahi/resolved conflict this spec addresses.

2. **Arch Wiki — Samba § "Browsing" network fails with "Failed to retrieve share list from server"**: Documents the NetBIOS conntrack helper fix (`iptables -t raw -A OUTPUT -p udp -m udp --dport 137 -j CT --helper netbios-ns`).

3. **Arch Wiki — GVfs § GNOME Files, Nemo, Caja, Thunar and PCManFM**: Confirms gvfs-smb is required for SMB browsing in Nautilus. On NixOS with GNOME, this is auto-enabled.

4. **NixOS Wiki — Samba**: Confirms `samba4Full` is needed for server-side mDNS registration but NOT for client-side browsing. Documents WSDD configuration.

5. **NixOS Wiki — GNOME**: Confirms GNOME module auto-enables gvfs and that dconf can be configured declaratively.

6. **Arch Wiki — Avahi § systemd-resolved prevents nss-mdns from working**: Documents the specific mechanism where resolved's mDNS handling prevents Avahi's nss-mdns module from functioning correctly.

7. **systemd resolved.conf(5) man page**: Documents `MulticastDNS=` and `LLMNR=` settings. Default is `yes` for both in systemd v256+.

8. **Avahi upstream issue #117**: Documents hostname race conditions when both Avahi and resolved handle mDNS simultaneously.

9. **Previous vexos-nix spec: `smb_nfs_discovery_spec.md`**: Thorough analysis of WSDD discovery mode (v4 fix). Confirmed gvfs backends are compiled with samba/avahi support. Identified WSDD as the fix for Windows hosts. Did not address resolved mDNS conflict (the remaining gap).

10. **GVfs source — `daemon/gvfsbackenddnssd.c`**: gvfsd-dnssd connects to Avahi's D-Bus interface (`org.freedesktop.Avahi`) to browse for `_smb._tcp`, `_nfs._tcp`, and other service types. If Avahi's service browser is impaired by resolved conflict, this backend returns no results.

11. **NixOS `nixos/modules/system/boot/resolved.nix`**: Defines `services.resolved.extraConfig` option for passing raw settings to `resolved.conf`.

12. **NixOS `nixos/modules/services/networking/firewall.nix`**: Defines `networking.firewall.extraCommands` for appending iptables rules.

---

## 11. Summary for Orchestrator

- **Root cause**: systemd-resolved's built-in MulticastDNS handler conflicts with Avahi, preventing Avahi's service browser from receiving NAS mDNS advertisements (`_smb._tcp`). This was never addressed in the four prior fix attempts which focused on WSDD and smb.conf.

- **Primary fix**: In `modules/network.nix`, add `extraConfig = "MulticastDNS=no\nLLMNR=no\n"` to `services.resolved` to disable resolved's mDNS handler, making Avahi the sole mDNS service.

- **Secondary fix**: In `modules/network-desktop.nix`, add a NetBIOS conntrack helper iptables rule via `networking.firewall.extraCommands` to fix traditional SMB browsing.

- **Files modified**: `modules/network.nix`, `modules/network-desktop.nix`

- **No new files, no new inputs, no `lib.mkIf` guards, no import changes.**

- **Spec file path**: `.github/docs/subagent_docs/smb_autodiscovery_spec.md`
