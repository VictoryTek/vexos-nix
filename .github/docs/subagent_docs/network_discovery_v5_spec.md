# Network Discovery v5 — Research & Specification

**Phase:** 1 — Research & Specification  
**Date:** 2026-05-09  
**Roles affected:** `desktop`, `htpc`, `stateless`, `server` (all roles that import `modules/network-desktop.nix`)  
**Prior attempts:** v1–v4 (see archived specs in this directory)

---

## 0. TL;DR for Orchestrator

Two distinct problems coexist, one fixable from NixOS configuration and one not:

**Problem A (NixOS bug — fixable):** `/etc/samba/smb.conf` is inaccessible because `/etc/samba/` does not exist on the live system.  `systemd.tmpfiles.settings."10-samba-etc"` was supposed to create the `/etc/samba → /etc/static/samba` symlink but is NOT being processed by systemd. Confirmed via: `ls /etc/samba/` → `No such file or directory`; `nmblookup WORKGROUP` → `Can't load /etc/samba/smb.conf - run testparm to debug it`. Fix: replace `systemd.tmpfiles.settings` with `systemd.tmpfiles.rules`.

**Problem B (NAS-side — not fixable from NixOS):** The NAS devices on the network do not advertise via any protocol that GNOME's Network view supports (Avahi mDNS `_smb._tcp` / `_nfs._tcp`, or WS-Discovery). Confirmed via: `avahi-browse -art` (8-second scan) found ZERO NAS file-sharing services; per-user `wsdd --no-host --discovery` probe sent on eno1 and got ZERO responses in 5 seconds; `gio list network://` is empty. The NAS devices must have Avahi/mDNS AND/OR WS-Discovery enabled on their own admin interfaces for auto-discovery to work.

**Additional fix (correctness):** The "SMB1 conversion" the user references removed `"client min protocol" = "SMB2"` but never added `"client min protocol" = "NT1"`. Without it, Samba 4.x defaults to `SMB2_02` minimum — SMB1 is still disabled. The explicit `NT1` must be set for the intent to be realised.

---

## 1. Diagnostic Results (live system — 2026-05-09)

| Check | Result |
|---|---|
| `systemctl is-active avahi-daemon samba-wsdd` | `active active` |
| `ls /etc/samba/` | `No such file or directory` |
| `/etc/static/samba/smb.conf` | EXISTS → `/nix/store/0vbnlw5na7w6w9jmn1cdzhbld9sfw4d9-smb.conf` |
| `systemd-tmpfiles --cat-config \| grep samba` | NO MATCH — rule not processed |
| `avahi-browse -art` for `_smb._tcp` / `_nfs._tcp` | **ZERO results** |
| `avahi-browse -art` for other services | Finds Roku (192.168.101.78/155), Home Assistant (192.168.100.34), vexos itself |
| wsdd discovery probe (eno1) | Sent — NO responses received in 5 s |
| `/run/wsdd/` | EXISTS (permission denied — created by samba-wsdd service) |
| `/run/user/1000/gvfsd/wsdd` | EXISTS (per-user wsdd for gvfsd-wsdd) |
| `gio list network://` | EMPTY |
| `nmblookup WORKGROUP` | `Can't load /etc/samba/smb.conf — name_query failed` |
| `ip route` | Default via 192.168.100.1 dev eno1 (Tailscale NOT default route — not a factor) |
| `enp3s0` | Alt name for eno1 (same physical NIC) |
| `enp104s0f3u1u2` | USB ethernet adapter, NO-CARRIER (not connected) |
| smb.conf content | `workgroup=WORKGROUP`, `server string=NixOS`, `server role=standalone`, `load printers=no` — NO `client min protocol` |
| Avahi network scope | 192.168.100.x and 192.168.101.x visible on eno1 (same L2 broadcast domain) |

---

## 2. Root Cause Analysis

### 2.1 `/etc/samba/` missing (Problem A)

`systemd.tmpfiles.settings."10-samba-etc"` generates a Nix package that installs to `/run/current-system/sw/lib/tmpfiles.d/10-samba-etc.conf`. However `systemd-tmpfiles --cat-config` shows no samba rule. The rule is present in the nix store but is not in the paths systemd actually processes at boot/activation:

- `/etc/tmpfiles.d/` — does NOT exist on the live system
- `/run/tmpfiles.d/` — only has `static-nodes.conf` and `dbus.conf`
- `/usr/lib/tmpfiles.d/` — has the standard static entries

`systemd.tmpfiles.rules` (a list of rule strings) writes rules to a file that NixOS's activation script places in `/etc/tmpfiles.d/` and also processes immediately via `systemd-tmpfiles --create`. This is the correct mechanism for per-system rules.

### 2.2 WS-Discovery not finding NAS devices (Problem B)

wsdd IS sending probes correctly on eno1 (192.168.100.93) to 239.255.255.250. The NAS devices are not responding. This is definitively NOT a NixOS firewall or multicast routing issue:

- Default route is via eno1 (Tailscale does not capture multicast routing)
- `services.samba-wsdd.openFirewall = true` opens UDP 3702 and TCP 5357
- wsdd probe delivery confirmed (wsdd verbose shows `scheduling Probe message via eno1`)

The NAS devices must have WS-Discovery disabled or not implemented. Common NAS firmwares require explicit enablement of WS-Discovery (e.g., Synology Control Panel → File Services → SMB → Advanced Settings → Enable WS-Discovery).

### 2.3 Avahi not finding NAS services (Problem B)

8-second `avahi-browse` scan found ZERO `_smb._tcp` / `_nfs._tcp` / `_afpovertcp._tcp` entries. The mDNS infrastructure works (finds Roku, Home Assistant, vexos itself). NAS devices simply do not advertise file-sharing services via mDNS. This requires enabling Avahi/Bonjour on the NAS admin interface.

### 2.4 SMB1 not actually enabled (correctness issue)

The "SMB1 conversion" removed `"client min protocol" = "SMB2"`. Without an explicit `"client min protocol" = "NT1"`, Samba 4.13+ defaults to `SMB2_02`. SMB1 is still disabled. For the intent to be realised, `"client min protocol" = "NT1"` must be explicitly set.

---

## 3. What the GNOME Network View Actually Requires

For NAS devices to appear in Nautilus → Other Locations → Network:

| Discovery method | Protocol | NAS requirement | gvfs backend |
|---|---|---|---|
| Avahi DNS-SD | UDP 5353 mDNS | NAS publishes `_smb._tcp`, `_nfs._tcp`, etc. | `gvfsd-dnssd` |
| WS-Discovery | UDP 3702 multicast | NAS responds to WSD Probe | `gvfsd-wsdd` |

`gvfsd-smb-browse` (NetBIOS workgroup enumeration) does **NOT** feed into the Network view `network://` location. It only serves `smb://` URI navigation (manual).

---

## 4. Proposed Solution

### 4.1 Fix Problem A: `/etc/samba/` symlink

**Replace** `systemd.tmpfiles.settings."10-samba-etc"` **with** `systemd.tmpfiles.rules`.

The `rules` list is the correct way to add per-system tmpfiles rules that NixOS's activation script processes immediately. The format string `"L+ /etc/samba - - - - /etc/static/samba"` creates the symlink atomically, replacing any existing content at `/etc/samba`.

```nix
# Before (broken):
systemd.tmpfiles.settings."10-samba-etc" = {
  "/etc/samba" = {
    "L+" = {
      argument = "/etc/static/samba";
    };
  };
};

# After (correct):
systemd.tmpfiles.rules = [
  "L+ /etc/samba - - - - /etc/static/samba"
];
```

### 4.2 Fix correctness: Enable SMB1 explicitly

Add `"client min protocol" = "NT1"` to the samba global settings. This genuinely allows libsmbclient and gvfsd-smb-browse to connect to NAS devices that only support SMB1.

```nix
settings.global = {
  workgroup              = "WORKGROUP";
  "server string"        = "NixOS";
  "server role"          = "standalone";
  "load printers"        = "no";
  "client min protocol"  = "NT1";   # ← ADD THIS
};
```

### 4.3 NAS-side requirements (not a NixOS change)

For auto-discovery to work in the GNOME Network view, **each NAS device needs at least one of:**

- **Avahi/Bonjour enabled**: Synology → Control Panel → File Services → Advanced → Enable Bonjour service discovery; QNAP → Network Services → mDNS (Bonjour)
- **WS-Discovery enabled**: Synology → Control Panel → File Services → SMB → Advanced Settings → Enable WS-Discovery; QNAP → Network Services → WS-Discovery

---

## 5. Files to Modify

| File | Change |
|---|---|
| `modules/network-desktop.nix` | (1) Replace `systemd.tmpfiles.settings."10-samba-etc"` with `systemd.tmpfiles.rules = [ "..." ]`; (2) Add `"client min protocol" = "NT1"` to `services.samba.settings.global` |

No other files require changes. No import-list changes required.

---

## 6. Risks and Mitigations

| Risk | Mitigation |
|---|---|
| `systemd.tmpfiles.rules` merges with other rules | `L+` replaces existing content — idempotent and safe |
| SMB1 re-enabling has security implications (EternalBlue-class vulnerabilities) | SMB1 is client-only (smbd disabled); vexos never serves SMB1; risk is outbound connections to compromised SMB1 servers only; acceptable for a home desktop |
| `/etc/samba` symlink pointing to `/etc/static/samba` causes stale link after samba config changes | `/etc/static/samba` is updated by NixOS activation on every rebuild; no stale risk |

---

## 7. Out of Scope

- Configuring NAS devices (requires NAS admin access, not NixOS)
- Making gvfsd-smb-browse feed into the `network://` namespace (not supported by gvfs architecture)
- Enabling mDNS reflection (only needed if NAS is on a truly separate L3 subnet — not the case here; 192.168.100.x and 192.168.101.x share L2)
