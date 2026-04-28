# Network Share Discovery v2 — Specification

## Feature Name
`network_share_discovery_v2`

## Date
2026-04-27

---

## 1. Why the Previous Attempt Failed

### What Was Implemented (v1)

The previous implementation in `modules/network-desktop.nix` added:

1. `services.avahi.publish.enable = true` + `publish.userServices = true`
2. `services.samba-wsdd.enable = true` + `openFirewall = true`
3. `boot.supportedFilesystems = [ "nfs" ]`
4. `samba` package in `environment.systemPackages`

### Root Cause: Missing `/etc/samba/smb.conf`

**The critical missing piece is `/etc/samba/smb.conf`.** Without it, the GVfs SMB browsing backend (`gvfsd-smb-browse`) cannot function.

Here is the discovery chain that Nautilus uses when the user clicks "Network" in the sidebar:

```
Nautilus → "network:///" URI
  → gvfsd-network (aggregator daemon)
    → gvfsd-dnssd      (DNS-SD/mDNS via Avahi — discovers hosts advertising _smb._tcp, etc.)
    → gvfsd-smb-browse  (SMB workgroup browsing via libsmbclient)
    → gvfsd-wsdd        (WS-Discovery — discovers Windows 10+ hosts)  [gvfs 1.54+]
```

The `gvfsd-smb-browse` daemon calls libsmbclient's `smbc_opendir("smb://")` to enumerate SMB workgroups and hosts. **libsmbclient requires `/etc/samba/smb.conf` to exist** — even a minimal one. Without it, libsmbclient fails to initialize and SMB network browsing returns zero results.

This is confirmed by the Arch Wiki: *"smbclient requires a /etc/samba/smb.conf file, which you can create as an empty file using the touch utility."*

### Why Ubuntu/Fedora Work Out of the Box

On Ubuntu and Fedora, the `samba-common` package (installed by default) provides `/etc/samba/smb.conf` with a minimal configuration including `workgroup = WORKGROUP`. On NixOS, simply adding the `samba` package to `environment.systemPackages` provides the binaries (`smbclient`, `nmblookup`) but does **NOT** create `/etc/samba/smb.conf`. The config file is only generated when `services.samba.enable = true` is set.

### Why Each v1 Change Was Insufficient

| Change | What It Actually Does | Why It Doesn't Fix Discovery |
|--------|----------------------|------------------------------|
| `avahi.publish.enable` | Makes THIS machine advertise services via mDNS | Does not help discover OTHER machines |
| `samba-wsdd.enable` | Makes THIS machine visible to Windows via WSD | Does not help Nautilus discover Windows machines (that's gvfsd-wsdd's job, which needs the SMB browsing stack working) |
| `boot.supportedFilesystems = ["nfs"]` | Loads NFS kernel modules for mounting | Does not affect network discovery |
| `samba` in systemPackages | Provides CLI binaries | Does NOT create smb.conf |

**All four changes are useful additions (visibility, mounting support, CLI tools) but none address the core requirement: libsmbclient needs smb.conf.**

---

## 2. Complete Discovery Architecture

### How Network Browsing Works in Nautilus

Three independent discovery mechanisms feed into the "Network" view:

#### 1. DNS-SD / mDNS (via Avahi)
- **Daemon:** `gvfsd-dnssd`
- **Mechanism:** Queries Avahi D-Bus API for services like `_smb._tcp`, `_nfs._tcp`, `_sftp-ssh._tcp`
- **Discovers:** Linux/macOS machines and NAS devices that advertise via mDNS/Bonjour
- **Requirements:** Avahi running (`services.avahi.enable = true`) — already configured in `network.nix`
- **Status:** ✅ Should already work for hosts advertising services via mDNS

#### 2. SMB Workgroup Browsing (via libsmbclient)
- **Daemon:** `gvfsd-smb-browse`
- **Mechanism:** Uses libsmbclient to enumerate SMB workgroups and hosts via NetBIOS/SMB queries
- **Discovers:** Windows machines, Samba servers, NAS devices in the SMB workgroup
- **Requirements:** `/etc/samba/smb.conf` with at minimum a `[global]` section defining `workgroup`
- **Status:** ❌ **BROKEN** — no smb.conf exists

#### 3. WS-Discovery (gvfs built-in)
- **Daemon:** `gvfsd-wsdd` (built into gvfs 1.54+, confirmed by `GVFS_WSDD_DEBUG` env var in gvfs docs)
- **Mechanism:** Uses WS-Discovery protocol to find Windows 10+ and Samba hosts advertising via WSD
- **Discovers:** Modern Windows machines that no longer use NetBIOS
- **Requirements:** The gvfs package with WSD support (compiled in on NixOS) + smb.conf for follow-up connections
- **Status:** ⚠️ Partially working (gvfs has built-in wsdd, but follow-up SMB connections need smb.conf)

### GVfs Package Build Verification

The NixOS `gvfs` package (`pkgs/by-name/gv/gvfs/package.nix`) includes:
- `samba` in `buildInputs` (when `udevSupport = true`, default on Linux) → SMB backend compiled in
- `avahi` in `buildInputs` (always) → DNS-SD backend compiled in
- `libnfs` in `buildInputs` (always) → NFS backend compiled in

The meson build flags confirm: `-Dsmb=false` is only set when `samba == null`, and `-Ddnssd=false` only when `avahi == null`. Both are provided, so both backends are enabled. ✅

### GVfs Service Activation

`services.desktopManager.gnome.enable = true` (set in `modules/gnome.nix` line 65) triggers the GNOME NixOS module, which sets:
- `services.gvfs.enable = true` (line 386 of nixpkgs GNOME module)
- `services.gnome.glib-networking.enable = true` (GIO network modules for TLS)

This means gvfs is properly installed with D-Bus service files and systemd user services. ✅

---

## 3. Complete Solution

### The Fix: Enable `services.samba` with Client-Only Configuration

Use the NixOS `services.samba` module to generate `/etc/samba/smb.conf` while keeping all server daemons disabled:

```nix
services.samba = {
  enable = true;
  smbd.enable = lib.mkDefault false;      # no file-sharing server
  nmbd.enable = lib.mkDefault false;      # no NetBIOS name service
  winbindd.enable = lib.mkDefault false;  # no Windows domain integration
  settings.global = {
    workgroup = "WORKGROUP";
    "client min protocol" = "SMB2";
    "client max protocol" = "SMB3";
    "load printers" = false;
  };
};
```

**Why `services.samba.enable` instead of `environment.etc."samba/smb.conf"`:**
- Idiomatic NixOS — uses the proper module infrastructure
- The NixOS samba module automatically adds the `samba` package to `environment.systemPackages`
- If a server role later needs actual SMB sharing, it can override daemon settings (the `lib.mkDefault false` allows this)
- No risk of duplicate `environment.etc` definitions conflicting

**Why `lib.mkDefault false` for daemons:**
- `lib.mkDefault` is a priority mechanism (priority 1000), NOT a conditional guard
- It allows any future module (e.g., a server module) to override with a plain `true` (priority 100) without conflict
- The project already uses `lib.mkDefault` in `modules/network.nix` (`networking.hostName = lib.mkDefault "vexos"`)

### Remove Redundant Package

Since `services.samba.enable = true` adds `pkgs.samba` to `environment.systemPackages` automatically via the NixOS module, the explicit `samba` entry in the `environment.systemPackages` list in `network-desktop.nix` should be removed to avoid duplication.

---

## 4. What Exists vs What's Needed

| Component | Current Status | Required | Action |
|-----------|---------------|----------|--------|
| `/etc/samba/smb.conf` | ❌ Missing | ✅ Critical | Add `services.samba.enable = true` with client-only config |
| `samba` package | ✅ In systemPackages | ✅ Needed | Remove from systemPackages (auto-added by samba module) |
| `services.avahi.enable` | ✅ In `network.nix` | ✅ Needed | No change |
| `services.avahi.nssmdns4` | ✅ In `network.nix` | ✅ Needed | No change |
| `services.avahi.publish` | ✅ In `network-desktop.nix` | ✅ Useful | No change |
| `services.samba-wsdd` | ✅ In `network-desktop.nix` | ✅ Useful | No change |
| `boot.supportedFilesystems = ["nfs"]` | ✅ In `network-desktop.nix` | ✅ Useful | No change |
| `services.gvfs.enable` | ✅ Auto-set by GNOME module | ✅ Critical | No change |
| `services.gnome.glib-networking` | ✅ Auto-set by GNOME module | ✅ Needed | No change |
| `cifs-utils` | ✅ In `network.nix` | ✅ Needed | No change |

---

## 5. Affected Roles

All four GNOME-based roles import `modules/network-desktop.nix`:

| Role | Configuration File | Imports `network-desktop.nix` |
|------|-------------------|-------------------------------|
| Desktop | `configuration-desktop.nix` | ✅ Line 14 |
| HTPC | `configuration-htpc.nix` | ✅ Line 11 |
| Server | `configuration-server.nix` | ✅ Line 13 |
| Stateless | `configuration-stateless.nix` | ✅ Line 11 |
| Headless Server | `configuration-headless-server.nix` | ❌ Not imported (correct) |

No changes to import lists are needed.

---

## 6. Architecture Compliance

### Module Placement

Per **Option B: Common base + role additions**:
- `modules/network.nix` (universal base) — Contains Avahi base, SSH, Tailscale, firewall, DNS resolver, cifs-utils. Imported by ALL roles including headless-server. **No change needed.**
- `modules/network-desktop.nix` (display-role additions) — Contains network discovery features for Nautilus. Only imported by display roles. **This is where the fix goes.**

### No Conditional Logic

The proposed changes use NO `lib.mkIf` guards. All content applies unconditionally to every role that imports the module. The `lib.mkDefault` on daemon enable flags is a priority mechanism for clean module composition, not conditional gating.

### Single File Modified

Only `modules/network-desktop.nix` is modified. No new files. No import list changes.

---

## 7. Implementation Steps

### Step 1: Modify `modules/network-desktop.nix`

Replace the current content with:

```nix
# modules/network-desktop.nix
# Display-role networking additions: SMB/NFS network share discovery for GNOME
# Files (Nautilus), Samba client configuration, and WSD visibility.
#
# Import in any configuration with a display (desktop, server, htpc, stateless).
# Do NOT import on headless-server.
{ config, pkgs, lib, ... }:
{
  # ── Samba client configuration ───────────────────────────────────────────
  # Enables the NixOS samba module to generate /etc/samba/smb.conf — required
  # by libsmbclient (used by GVfs gvfsd-smb-browse) to enumerate SMB
  # workgroups and hosts in the Nautilus "Network" view.
  #
  # Ubuntu/Fedora ship a default smb.conf via samba-common; NixOS only
  # creates one when services.samba.enable is true.  Without smb.conf,
  # gvfsd-smb-browse silently returns zero results and the Network view
  # stays empty.
  #
  # All server daemons default to off (client-only).  A server role that
  # needs actual file sharing can override with a plain `smbd.enable = true`.
  services.samba = {
    enable = true;
    smbd.enable      = lib.mkDefault false;   # no file-sharing server
    nmbd.enable      = lib.mkDefault false;   # no NetBIOS name service
    winbindd.enable  = lib.mkDefault false;   # no Windows domain integration
    settings.global = {
      workgroup            = "WORKGROUP";
      "client min protocol" = "SMB2";
      "client max protocol" = "SMB3";
      "load printers"      = false;
    };
  };

  # ── Avahi service publishing ─────────────────────────────────────────────
  # Extends the base Avahi configuration in network.nix with service
  # publishing.  publish.enable + publish.userServices allow Avahi to
  # advertise this machine's services via mDNS/DNS-SD so other machines
  # running Nautilus, Finder, or similar can discover this host.
  services.avahi.publish = {
    enable       = true;
    userServices = true;
  };

  # ── WS-Discovery (WSDD) ─────────────────────────────────────────────────
  # Web Service Discovery responder — makes this machine visible to
  # Windows 10+ "Network" view and other WSD clients.
  # Opens TCP 5357 and UDP 3702 via openFirewall.
  services.samba-wsdd = {
    enable       = true;
    openFirewall = true;
  };

  # ── NFS client support ──────────────────────────────────────────────────
  # Loads the NFS kernel module and pulls in nfs-utils so that GVfs can
  # mount NFS shares discovered via Nautilus → Network → nfs://host/export.
  boot.supportedFilesystems = [ "nfs" ];
}
```

### Step 2: Verify No Import Changes Needed

All four GNOME-based `configuration-*.nix` files already import `./modules/network-desktop.nix`. No changes to import lists are required.

### Step 3: Validate Build

- `nix flake check`
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd`
- `sudo nixos-rebuild dry-build --flake .#vexos-htpc-amd`
- `sudo nixos-rebuild dry-build --flake .#vexos-server-amd`
- `sudo nixos-rebuild dry-build --flake .#vexos-stateless-amd`

---

## 8. Dependencies

### NixOS Services (no new flake inputs)

| Service/Option | NixOS Module | Package | Status |
|---------------|-------------|---------|--------|
| `services.samba` | `nixos/modules/services/network-filesystems/samba.nix` | `pkgs.samba` | **NEW** — generates smb.conf |
| `services.avahi.publish` | `nixos/modules/services/networking/avahi-daemon.nix` | `pkgs.avahi` (already present) | Existing |
| `services.samba-wsdd` | `nixos/modules/services/network-filesystems/samba-wsdd.nix` | `pkgs.wsdd` | Existing |
| `boot.supportedFilesystems = ["nfs"]` | `nixos/modules/tasks/filesystems/nfs.nix` | `pkgs.nfs-utils` | Existing |

No new flake inputs. All packages come from nixpkgs. No `nixpkgs.follows` changes needed.

### Firewall Ports

| Port | Protocol | Service | Direction | Status |
|------|----------|---------|-----------|--------|
| UDP 5353 | mDNS | Avahi | Inbound | Pre-existing (`network.nix`) |
| TCP 5357 | WSD HTTP | WSDD | Inbound | Pre-existing (`network-desktop.nix`) |
| UDP 3702 | WSD multicast | WSDD | Inbound | Pre-existing (`network-desktop.nix`) |
| TCP 445 | SMB | smbd | **NOT opened** | `services.samba.openFirewall` defaults to `false`; no server daemons running |

**No new firewall ports are opened.** The samba service is client-only.

---

## 9. Configuration Changes

### Before (current `modules/network-desktop.nix`)

```nix
{ pkgs, ... }:
{
  services.avahi.publish = {
    enable       = true;
    userServices = true;
  };

  services.samba-wsdd = {
    enable       = true;
    openFirewall = true;
  };

  boot.supportedFilesystems = [ "nfs" ];

  environment.systemPackages = with pkgs; [
    samba
  ];
}
```

### After (proposed `modules/network-desktop.nix`)

```nix
{ config, pkgs, lib, ... }:
{
  services.samba = {
    enable = true;
    smbd.enable      = lib.mkDefault false;
    nmbd.enable      = lib.mkDefault false;
    winbindd.enable  = lib.mkDefault false;
    settings.global = {
      workgroup            = "WORKGROUP";
      "client min protocol" = "SMB2";
      "client max protocol" = "SMB3";
      "load printers"      = false;
    };
  };

  services.avahi.publish = {
    enable       = true;
    userServices = true;
  };

  services.samba-wsdd = {
    enable       = true;
    openFirewall = true;
  };

  boot.supportedFilesystems = [ "nfs" ];
}
```

### Key Differences

1. **Added:** `services.samba` block with client-only configuration → creates `/etc/samba/smb.conf`
2. **Removed:** `environment.systemPackages = [ samba ]` → redundant; samba module adds it automatically
3. **Added:** `lib` to function arguments (needed for `lib.mkDefault`)
4. **Added:** `config` to function arguments (future-proofing for NixOS module system)
5. **Changed:** Module header comment updated to reflect broader scope

---

## 10. Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| `services.samba.enable = true` accidentally starts smbd | Low | Medium | All daemon `.enable` flags set to `lib.mkDefault false`; no firewall ports opened; no shares defined |
| Future server module conflict with samba settings | Low | Low | `lib.mkDefault` allows override; `settings.global` merges cleanly via NixOS module system |
| SMB workgroup browsing still empty on modern networks | Medium | Low | Expected: Windows 10+ machines may not appear via NetBIOS browsing. They should appear via gvfs's built-in WSD backend. NAS devices and Linux machines appear via DNS-SD. |
| smb.conf `workgroup = WORKGROUP` doesn't match actual network | Low | Low | WORKGROUP is the universal default used by Windows, macOS, Samba, and every NAS. User can override via a role-specific module if needed. |
| Build failure from samba module activation | Very Low | Medium | The samba NixOS module is well-tested; client-only config is minimal; build validation catches issues |

---

## 11. Post-Deployment Verification

After deploying, verify the fix with these commands:

```bash
# 1. Confirm smb.conf exists and has correct content
cat /etc/samba/smb.conf

# 2. Confirm no samba server daemons are running
systemctl status smbd nmbd winbindd  # all should be inactive/disabled

# 3. Test Avahi DNS-SD discovery
avahi-browse -a -t  # should list discovered services on the network

# 4. Test SMB browsing via smbclient
smbclient -L WORKGROUP -N  # should not error about missing smb.conf

# 5. Test Nautilus
# Open GNOME Files → click "Network" in the sidebar
# Network shares from other machines should now appear
```

---

## 12. Research Sources

1. **NixOS nixpkgs GNOME module** (`nixos/modules/services/desktop-managers/gnome.nix`) — confirms `services.gvfs.enable = true` is auto-set by GNOME
2. **NixOS nixpkgs gvfs service** (`nixos/modules/services/desktops/gvfs.nix`) — confirms gvfs package, D-Bus, and systemd integration
3. **NixOS nixpkgs gvfs package** (`pkgs/by-name/gv/gvfs/package.nix`) — confirms SMB, DNS-SD, NFS backends compiled in; samba and avahi in buildInputs
4. **NixOS nixpkgs samba module** (`nixos/modules/services/network-filesystems/samba.nix`) — confirms smbd/nmbd/winbindd enable options with defaults
5. **Arch Wiki: GVFS / File Manager Functionality** — documents gvfs-smb requirement for SMB browsing; lists gvfs backend packages
6. **Arch Wiki: Samba** — notes "smbclient requires a /etc/samba/smb.conf file"; documents client configuration
7. **NixOS Wiki: Samba** — shows NixOS-specific configuration patterns including client CIFS mount and GVFS browsing
8. **GNOME GVfs documentation** (wiki.gnome.org/Projects/gvfs/doc) — documents architecture: gvfsd-network aggregates gvfsd-dnssd + gvfsd-smb-browse + gvfsd-wsdd; confirms `GVFS_SMB_DEBUG` and `GVFS_WSDD_DEBUG` env vars exist
9. **NixOS nixpkgs Avahi module** (`nixos/modules/services/networking/avahi-daemon.nix`) — confirms publish settings and service file configuration
10. **NixOS search options** (search.nixos.org) — confirms `services.samba.smbd.enable`, `services.samba.nmbd.enable`, `services.samba.winbindd.enable` options exist
