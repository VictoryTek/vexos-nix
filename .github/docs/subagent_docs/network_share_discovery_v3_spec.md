# Network Share Discovery v3 — Research & Specification

## Feature Name
`network_share_discovery_v3`

## Date
2026-04-27

## Problem Statement
Two previous attempts (v1 and v2) to enable SMB/NFS network share auto-discovery
in GNOME Files (Nautilus) have FAILED. Shares do not appear in the Nautilus
"Network" tab or when manually browsing `smb://`. This third attempt is informed
by exhaustive live system diagnostics and root cause analysis.

---

## Part 1: Live System Diagnostic Results

### 1.1 GVfs State

| Item | Finding |
|------|---------|
| GVfs version | 1.58.4 (three store paths in closure) |
| Active gvfs-daemon | Running at `/nix/store/s609f19ny...-gvfs-1.58.4/libexec/gvfsd` |
| gvfsd-fuse | Running, mounted at `/run/user/1000/gvfs` |
| gvfsd-smb-browse | Binary EXISTS in store but NOT running (on-demand activation — normal) |
| gvfsd-network | Binary EXISTS in store but NOT running (on-demand activation — normal) |
| gvfsd-smb | Binary EXISTS in store |
| gvfsd-dnssd | Binary EXISTS in store |
| gvfsd-wsdd | Binary EXISTS in store |
| GVfs mount definitions | ALL present: `smb.mount`, `smb-browse.mount`, `network.mount`, `dns-sd.mount`, `wsdd.mount` |
| GVfs D-Bus services | Present: Daemon, UDisks2, MTP, GPhoto2, GOA, AFC volume monitors |
| Missing D-Bus services | No SMB-specific volume monitor (expected — SMB uses on-demand mount activation) |
| `GIO_EXTRA_MODULES` | Set correctly, includes gvfs-1.58.4 |
| `XDG_DATA_DIRS` | Includes `/run/current-system/sw/share/` (mount definitions accessible) |

### 1.2 GVfs SMB Backend Compilation

| Item | Finding |
|------|---------|
| Samba in gvfs closure | YES — samba-4.23.5 is a runtime dependency |
| `gvfsd-smb` links libsmbclient | YES — `.gvfsd-smb-wrapped` links `libsmbclient.so.0` from samba-4.23.5 |
| `gvfsd-smb-browse` links libsmbclient | YES — `.gvfsd-smb-browse-wrapped` links `libsmbclient.so.0` |
| Meson build flags | SMB NOT disabled (only `-Dgcr=false -Dgoa=false -Dkeyring=false -Donedrive=false -Dgoogle=false`) |
| GVfs package variant | Base gvfs with `udevSupport=true` (SMB enabled), `gnomeSupport=false` (GOA/Keyring off — irrelevant for SMB) |

**Conclusion: GVfs IS correctly compiled with full SMB support.** The package is NOT the problem.

### 1.3 Samba / smb.conf State

| Item | Finding |
|------|---------|
| `services.samba.enable` | `true` (confirmed via `nix eval`) |
| NixOS samba module generates `environment.etc."samba/smb.conf"` | YES (confirmed in module source, line 223) |
| `/run/current-system/etc/samba/smb.conf` | EXISTS — symlink to nix store `smb.conf` |
| `/etc/static/samba/smb.conf` | EXISTS — symlink to nix store `smb.conf` |
| **`/etc/samba/`** | **DOES NOT EXIST** ❌ |
| **`/etc/samba/smb.conf`** | **DOES NOT EXIST** ❌ |
| smb.conf content (in nix store) | Valid: `workgroup=WORKGROUP, client min protocol=SMB2, security=user, server role=standalone` |
| `smbclient -N -L //localhost` | **FAILS**: `Can't load /etc/samba/smb.conf` |
| `samba.target` | Active |
| `samba-wsdd.service` | Active and running |
| `smbd` / `nmbd` / `winbindd` | Not running (correct — disabled by config) |

### 1.4 The Critical Failure: `gio mount smb://`

```
$ gio mount smb://
Failed to retrieve share list from server: No such file or directory
```

**This error occurs because:**
1. Nautilus / `gio` asks gvfsd to activate the `smb-browse` mount backend
2. gvfsd starts `gvfsd-smb-browse`
3. `gvfsd-smb-browse` calls `libsmbclient` to enumerate SMB workgroups/hosts
4. `libsmbclient` tries to load `/etc/samba/smb.conf`
5. **`/etc/samba/smb.conf` does not exist** → "No such file or directory"
6. `gvfsd-smb-browse` fails → Nautilus shows empty Network view

### 1.5 Avahi State

| Item | Finding |
|------|---------|
| `avahi-daemon` | Active and running |
| Host name | `vexos.local` |
| `services.avahi.nssmdns4` | `true` |
| `services.avahi.openFirewall` | `true` (UDP 5353 open) |
| `services.avahi.publish.enable` | `true` |
| `/etc/nsswitch.conf` hosts | `mymachines mdns4_minimal [NOTFOUND=return] resolve [!UNAVAIL=return] files myhostname dns mdns4` |

**Conclusion: Avahi/mDNS is correctly configured.** Not the problem.

### 1.6 Firewall State

| Port | Protocol | Status | Purpose |
|------|----------|--------|---------|
| 5353 | UDP | Open (avahi) | mDNS |
| 5357 | TCP | Open (samba-wsdd) | WS-Discovery |
| 3702 | UDP | Open (samba-wsdd) | WS-Discovery |
| 22 | TCP | Open (openssh) | SSH |
| 445 | TCP | NOT open inbound | SMB (outbound client OK, inbound not needed) |

**Conclusion: Firewall is correctly configured for client-only SMB.** Not the problem.

### 1.7 Network Interface State

| Item | Finding |
|------|---------|
| NetworkManager | Active |
| System uptime | 32 minutes (recently rebooted) |

---

## Part 2: Root Cause Analysis

### The Root Cause

**NixOS's `/etc/` activation failed to create the `/etc/samba/` directory.**

The NixOS samba module (line 223 of `samba.nix`) correctly declares:
```nix
environment.etc."samba/smb.conf".source = configFile;
```

This generates the file through the NixOS etc management chain:
1. ✅ `/nix/store/0nrg0p6miig...-smb.conf` — generated correctly
2. ✅ `/run/current-system/etc/samba/smb.conf` → nix store symlink
3. ✅ `/etc/static/samba/smb.conf` → nix store symlink
4. ❌ `/etc/samba/` — **NOT CREATED** by the etc activation script

On NixOS, the activation script (`switch-to-configuration`) is responsible for
creating entries in `/etc/` that mirror `/etc/static/`. For directory entries
like `samba/`, it should create the directory and populate it with symlinks.
This step failed silently.

**Likely cause**: The system was rebuilt (possibly via `nixos-rebuild boot` or
during initial setup), and the etc activation during boot did not correctly
process the new `samba/smb.conf` entry. This can happen when:
- The previous generation didn't have the entry (first time adding samba)
- The activation runs during boot before all filesystems are ready
- There's a race condition in the etc activation script

### Why v1 Failed
v1 added Avahi publishing, WSDD, and NFS support but did NOT add
`services.samba.enable = true`. Without this, no `/etc/samba/smb.conf` is
generated, and `libsmbclient` (used by `gvfsd-smb-browse`) cannot initialize.

### Why v2 Failed
v2 correctly added `services.samba.enable = true` with all daemons disabled.
The NixOS samba module correctly generates `smb.conf` and declares it in
`environment.etc`. The smb.conf content is correct and exists in the nix store
and in `/etc/static/samba/`. **However**, the NixOS etc activation failed to
create the `/etc/samba/` directory, so the file is not accessible at its
expected path. The v2 code is correct — the deployment failed.

---

## Part 3: Research Sources

1. **NixOS samba module source** (`nixos/modules/services/network-filesystems/samba.nix`):
   - Line 223: `environment.etc."samba/smb.conf".source = configFile;`
   - Uses `pkgs.formats.ini` to generate config from `services.samba.settings`
   - `services.samba.enable = true` is required for etc entry generation
   - `smbd.enable`, `nmbd.enable`, `winbindd.enable` default to `true` (must be overridden to `false` for client-only)

2. **NixOS gvfs module source** (`nixos/modules/services/desktops/gvfs.nix`):
   - Default package: `pkgs.gnome.gvfs` (which is `pkgs.gvfs.override { gnomeSupport = true; }`)
   - Module enables `services.gvfs.enable = true` via GNOME desktop module
   - Sets `environment.systemPackages`, D-Bus services, and systemd user units

3. **nixpkgs gvfs package** (`pkgs/by-name/gv/gvfs/package.nix`):
   - `samba` is a build input (always on Linux via `udevSupport`)
   - `gnomeSupport` controls GOA, GCR, Google Drive, OneDrive — NOT SMB
   - SMB backends (`gvfsd-smb`, `gvfsd-smb-browse`) always compiled on Linux

4. **NixOS nixpkgs issue #2880** — Historical: gvfs was once built without samba support.
   Fixed in 2014. Current package DOES include samba. Not the current issue.

5. **Arch Wiki — Samba § Discovering network shares**:
   - `smbclient` requires `/etc/samba/smb.conf` to exist
   - Client-only usage only needs an empty or minimal smb.conf
   - Modern discovery uses WSD/DNS-SD, not NetBIOS broadcasts

6. **Arch Wiki — GVFS / File manager functionality**:
   - `gvfs-smb` (equivalent to gvfs with samba) needed for SMB in Nautilus
   - Mount backends in `/usr/share/gvfs/mounts/` (NixOS: `/run/current-system/sw/share/gvfs/mounts/`)

7. **Arch Wiki — GNOME/Files § Windows machines don't show in Network view**:
   - Solution: install `gvfs-wsdd` for WS-Discovery support
   - Already present in vexos-nix (`gvfsd-wsdd` binary exists, `samba-wsdd` service running)

8. **GNOME GVfs source** (`gvfsbackendsmbbrowse.c`):
   - Uses `libsmbclient` API (`smbc_init`, `smbc_opendir`, `smbc_readdir`)
   - Requires smb.conf to be loadable by libsmbclient
   - Falls back to user's `~/.smb/smb.conf` if system config missing (but may not work reliably)

9. **NixOS Discourse — Samba connectivity issues**:
   - Common NixOS issue: samba config not being applied until reboot
   - `nixos-rebuild switch` should apply immediately, `boot` requires reboot

10. **gvfsd-smb-browse mount definition** (`smb-browse.mount`):
    - Exec: `/nix/store/.../libexec/gvfsd-smb-browse`
    - AutoMount: true
    - Scheme: smb
    - Type: network (appears in Nautilus Network view)

---

## Part 4: Complete Fix

### 4.1 Diagnosis: The v2 Config is Correct

The existing `modules/network-desktop.nix` from v2 is **correctly configured**.
The NixOS samba module properly generates smb.conf. The issue is that the NixOS
etc activation failed to create `/etc/samba/` on the running system.

### 4.2 Required Changes

**File: `modules/network-desktop.nix`**

Add a `systemd.tmpfiles.settings` entry that guarantees `/etc/samba/smb.conf`
is accessible, even if the NixOS etc activation has a timing issue. This uses
NixOS's structured tmpfiles API (not raw rules strings) to create a symlink
from `/etc/samba` to `/etc/static/samba` on every boot.

Additionally, add two minor improvements from the v2 review's RECOMMENDED items:
- `"client max protocol" = "SMB3"` — explicit upper bound
- `"load printers" = false` — suppress printer enumeration noise

### 4.3 Exact Changes to `modules/network-desktop.nix`

```nix
# modules/network-desktop.nix
# Display-role networking additions: SMB/NFS network share discovery for
# GNOME Files (Nautilus).
#
# Generates /etc/samba/smb.conf (client-only — all server daemons disabled)
# so that GVfs gvfsd-smb-browse can use libsmbclient to discover SMB hosts.
# Also enables Avahi service publishing, WS-Discovery (WSDD), and NFS
# kernel support.
#
# Import in any configuration with a display (desktop, server, htpc, stateless).
# Do NOT import on headless-server.
{ lib, ... }:
{
  # ── Samba client configuration ───────────────────────────────────────────
  # Generates /etc/samba/smb.conf so that libsmbclient (used by GVfs
  # gvfsd-smb-browse) can initialise and enumerate SMB workgroups/hosts.
  # All server daemons are disabled — this is client-only.  The NixOS samba
  # module automatically adds the samba package (smbclient, nmblookup) to
  # environment.systemPackages.
  #
  # lib.mkDefault on daemon enables lets a server role override to true
  # without conflicts.
  services.samba = {
    enable              = true;
    nmbd.enable         = lib.mkDefault false;
    smbd.enable         = lib.mkDefault false;
    winbindd.enable     = lib.mkDefault false;
    settings = {
      global = {
        workgroup            = "WORKGROUP";
        "server string"      = "NixOS";
        "server role"        = "standalone";
        "client min protocol" = "SMB2";
        "client max protocol" = "SMB3";
        "load printers"      = false;
      };
    };
  };

  # ── /etc/samba symlink safety net ────────────────────────────────────────
  # The NixOS samba module declares environment.etc."samba/smb.conf" which
  # should create /etc/samba/ during activation.  However, the etc
  # activation can fail silently on first deployment (new directory entry)
  # or after nixos-rebuild boot (boot-time activation race).  This tmpfiles
  # rule ensures /etc/samba exists as a symlink to /etc/static/samba on
  # every boot, guaranteeing that libsmbclient and gvfsd-smb-browse can
  # always find smb.conf.
  systemd.tmpfiles.settings."10-samba-etc" = {
    "/etc/samba" = {
      "L+" = {
        argument = "/etc/static/samba";
      };
    };
  };

  # ── Avahi service publishing ─────────────────────────────────────────────
  # Extends the base Avahi configuration in network.nix with service
  # publishing.  publish.enable + publish.userServices allow Avahi to
  # advertise this machine's services via mDNS/DNS-SD and enable GVfs to
  # discover remote hosts advertising _smb._tcp / _nfs._tcp services in
  # the Nautilus "Network" view.
  services.avahi.publish = {
    enable       = true;
    userServices = true;
  };

  # ── WS-Discovery (WSDD) ─────────────────────────────────────────────────
  # Web Service Discovery responder — required for discovering Windows 10+
  # machines and Samba servers that use WSD instead of legacy NetBIOS
  # browsing.  Also makes this machine visible to Windows "Network".
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

### 4.4 What Changed from v2

| Change | Reason |
|--------|--------|
| Added `systemd.tmpfiles.settings."10-samba-etc"` | Creates `/etc/samba` → `/etc/static/samba` symlink on every boot, fixing the root cause |
| Added `"client max protocol" = "SMB3"` | v2 review RECOMMENDED item — explicit upper bound |
| Added `"load printers" = false` | v2 review RECOMMENDED item — suppress printer enumeration |

### 4.5 How the tmpfiles Fix Works

1. NixOS samba module generates smb.conf → deployed to `/etc/static/samba/smb.conf`
2. `systemd.tmpfiles.settings."10-samba-etc"` creates `L+ /etc/samba - - - - /etc/static/samba`
3. The `L+` type means: create symlink, removing any existing file/directory/symlink first
4. systemd-tmpfiles runs early in boot (before user sessions start)
5. When gvfsd-smb-browse is activated on demand, it can find `/etc/samba/smb.conf`
6. libsmbclient loads config successfully → SMB browsing works

### 4.6 Why This Won't Conflict with NixOS etc Management

The `L+` tmpfiles type will create the symlink regardless of what exists.
If the NixOS etc activation later creates `/etc/samba/` properly, the tmpfiles
entry is a no-op (the symlink already points to the right place).
If the etc activation fails (the current bug), tmpfiles provides the fallback.
The tmpfiles rule runs during `systemd-tmpfiles-setup.service`, which runs
before `multi-user.target` and well before any user session starts.

---

## Part 5: Files to Modify

| File | Change |
|------|--------|
| `modules/network-desktop.nix` | Add tmpfiles rule, add `client max protocol`, add `load printers` |

No new files needed. No import changes needed. No other files affected.

---

## Part 6: Verification Steps

After applying changes and running `sudo nixos-rebuild switch --flake .#vexos-desktop-amd`:

1. **Check `/etc/samba/smb.conf` exists:**
   ```bash
   cat /etc/samba/smb.conf
   # Should show: workgroup=WORKGROUP, client min protocol=SMB2, etc.
   ```

2. **Check smbclient can load config:**
   ```bash
   smbclient --configfile /etc/samba/smb.conf -N -L //localhost 2>&1
   # Should NOT show "Can't load /etc/samba/smb.conf"
   # (Connection refused is expected — smbd is disabled)
   ```

3. **Check gio mount works:**
   ```bash
   gio mount smb://
   # Should NOT show "No such file or directory"
   # May show "Failed to retrieve share list" if no SMB servers on network — that's OK
   ```

4. **Check Nautilus Network tab:**
   - Open Files → Other Locations → Network
   - If SMB servers exist on the network, they should appear
   - If no SMB servers exist, the view will be empty (expected)

5. **Check tmpfiles created the symlink:**
   ```bash
   ls -la /etc/samba
   # Should show: /etc/samba -> /etc/static/samba
   ```

---

## Part 7: Risk Assessment

| Risk | Mitigation |
|------|-----------|
| tmpfiles `L+` overwrites existing /etc/samba | Only overwrites with a symlink to the correct target; no data loss |
| Conflict with NixOS etc activation | No conflict — both create the same path; tmpfiles wins on first boot, etc activation may update later |
| No SMB servers on network = empty Network tab | Expected behavior, not a bug; user can manually connect via `smb://host/share` |
| Future NixOS versions fix the etc activation | tmpfiles rule becomes a harmless no-op |

---

## Part 8: Dependencies

- No new external dependencies
- No new flake inputs
- No Context7 verification needed (no new libraries)
- Uses only existing NixOS module options (`systemd.tmpfiles.settings`)
