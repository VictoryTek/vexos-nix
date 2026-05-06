# Network Share Discovery Specification

## Feature Name
`network_share_discovery`

## Date
2026-04-27

---

## 1. Current State Analysis

### What Exists

| Component | File | Status |
|-----------|------|--------|
| Avahi (mDNS/DNS-SD) | `modules/network.nix` | ✅ `services.avahi.enable = true`, `nssmdns4 = true`, `openFirewall = true` |
| GVfs (GNOME Virtual FS) | Implicit via GNOME module | ✅ Auto-enabled by `services.desktopManager.gnome.enable = true` |
| `cifs-utils` (mount.cifs) | `modules/network.nix` | ✅ In `environment.systemPackages` |
| `samba` (smbclient/libsmbclient) | `modules/network-desktop.nix` | ✅ In `environment.systemPackages` (display roles only) |
| Nautilus overlay (unstable) | `modules/gnome.nix` | ✅ Nautilus pinned to nixpkgs-unstable |

### What Is Missing

| Component | Required For | Status |
|-----------|-------------|--------|
| `services.avahi.publish.enable` | mDNS service advertisement and bidirectional service browsing | ❌ Not configured |
| `services.avahi.publish.userServices` | User-level service publishing (Nautilus share advertisement) | ❌ Not configured |
| `services.samba-wsdd.enable` | WS-Discovery protocol — discover Windows 10+ / Samba hosts using WSD | ❌ Not configured |
| `boot.supportedFilesystems = [ "nfs" ]` | NFS kernel module + nfs-utils for GVfs NFS backend in Nautilus | ❌ Not configured |

### GNOME-Based Roles Affected

All four GNOME-based roles import both `modules/gnome.nix` (via their `gnome-<role>.nix`) and `modules/network-desktop.nix`:

| Role | Configuration File | Imports `network-desktop.nix` |
|------|-------------------|-------------------------------|
| Desktop | `configuration-desktop.nix` | ✅ Line 14 |
| HTPC | `configuration-htpc.nix` | ✅ Line 11 |
| Server | `configuration-server.nix` | ✅ Line 13 |
| Stateless | `configuration-stateless.nix` | ✅ Line 11 |
| Headless Server | `configuration-headless-server.nix` | ❌ Not imported (correct — no GUI) |

---

## 2. Problem Definition

SMB and NFS network shares do not automatically appear under the "Network" sidebar in GNOME Files (Nautilus). Users must manually type `smb://` or `nfs://` URIs to connect to network shares. This is a standard feature on mainstream GNOME-based distributions (Fedora, Ubuntu) that works out of the box.

### Root Cause

The NixOS GNOME module enables GVfs but does **not** automatically configure the network discovery stack that GVfs depends on for populating the Network view. Three discovery subsystems are missing:

1. **Avahi publish mode** — Without `publish.enable`, the Avahi daemon runs in receive-only mode. GVfs's network browsing relies on Avahi publishing/browsing service records (specifically `_smb._tcp` and `_nfs._tcp` service types) to populate the Network view. Enabling publish mode allows proper bidirectional mDNS/DNS-SD service discovery.

2. **WS-Discovery (WSDD)** — Windows 10 version 1709+ removed SMBv1/NetBIOS browsing and switched to the Web Service Discovery (WSD) protocol. Without a WSDD responder, Windows machines (and Samba servers configured for WSD) are invisible in the Network view. The `services.samba-wsdd` NixOS module provides the `wsdd` daemon.

3. **NFS client kernel support** — GVfs includes an NFS backend (via `libnfs`), but NFS kernel modules and `nfs-utils` are not loaded unless `boot.supportedFilesystems` includes `"nfs"`. Without this, NFS shares cannot be mounted after discovery.

---

## 3. Proposed Solution Architecture

### Module Placement Decision

Per the project's **Option B: Common base + role additions** architecture:

- **`modules/network.nix`** (universal base) — Already contains the Avahi base config. It is imported by ALL roles including headless-server. Network discovery features (WSDD, Avahi publish, NFS client) are only useful on display roles with Nautilus, so they must NOT go here.
- **`modules/network-desktop.nix`** (display-role additions) — Already serves as "display-role networking additions" and is imported by exactly the four GNOME-based roles. This is the correct location.

**Decision:** Modify `modules/network-desktop.nix` to add all three missing discovery components alongside the existing `samba` package.

No new module files are needed. No `configuration-*.nix` import lists change.

### Changes Summary

**Single file modified:** `modules/network-desktop.nix`

Add:
1. `services.avahi.publish.enable = true` and `services.avahi.publish.userServices = true`
2. `services.samba-wsdd.enable = true` and `services.samba-wsdd.openFirewall = true`
3. `boot.supportedFilesystems = [ "nfs" ]`

---

## 4. Implementation Steps

### Step 1: Modify `modules/network-desktop.nix`

Replace the current minimal module with the expanded version below:

```nix
# modules/network-desktop.nix
# Display-role networking additions: SMB/NFS network share discovery for GNOME
# Files (Nautilus) and samba CLI tools.
#
# Import in any configuration with a display (desktop, server, htpc, stateless).
# Do NOT import on headless-server.
{ pkgs, ... }:
{
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

  # ── SMB/CIFS client tools ────────────────────────────────────────────────
  # samba: provides smbclient CLI and libsmbclient (used by GVfs SMB
  # backend).  GNOME Files browses SMB shares via GVfs; smbclient is the
  # CLI companion.  Client-only — no inbound firewall ports needed.
  environment.systemPackages = with pkgs; [
    samba  # smbclient — browse/test SMB shares; also provides nmblookup
  ];
}
```

### Step 2: Verify No Import Changes Needed

All four GNOME-based `configuration-*.nix` files already import `./modules/network-desktop.nix`. No changes to import lists are required.

### Step 3: Validate Build

Run validation for at least one variant per role:
- `nix flake check`
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd`
- `sudo nixos-rebuild dry-build --flake .#vexos-htpc-amd`
- `sudo nixos-rebuild dry-build --flake .#vexos-server-amd`
- `sudo nixos-rebuild dry-build --flake .#vexos-stateless-amd`

---

## 5. Dependencies

### NixOS Services (no new flake inputs)

| Service/Option | NixOS Module | Package |
|---------------|-------------|---------|
| `services.avahi.publish` | `nixos/modules/services/networking/avahi-daemon.nix` | `pkgs.avahi` (already present) |
| `services.samba-wsdd` | `nixos/modules/services/network-filesystems/samba-wsdd.nix` | `pkgs.wsdd` (new — pulled in by service) |
| `boot.supportedFilesystems = ["nfs"]` | `nixos/modules/tasks/filesystems/nfs.nix` | `pkgs.nfs-utils` (new — pulled in by supportedFilesystems) |

No new flake inputs. All packages come from nixpkgs. No `nixpkgs.follows` changes needed.

### Firewall Ports Opened

| Port | Protocol | Service | Direction |
|------|----------|---------|-----------|
| UDP 5353 | mDNS | Avahi | Already open (`network.nix`: `services.avahi.openFirewall = true`) |
| TCP 5357 | WSD HTTP | WSDD | New (via `services.samba-wsdd.openFirewall = true`) |
| UDP 3702 | WSD multicast | WSDD | New (via `services.samba-wsdd.openFirewall = true`) |

---

## 6. Configuration Changes

### Before (current `modules/network-desktop.nix`)

```nix
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    samba
  ];
}
```

### After (proposed `modules/network-desktop.nix`)

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

### systemd Services Added

| Service | Description |
|---------|-------------|
| `wsdd.service` | WS-Discovery responder daemon — auto-started by `services.samba-wsdd.enable` |

### NixOS Module Merging Behavior

The NixOS module system merges attribute sets from multiple modules:

- `services.avahi.publish` in `network-desktop.nix` merges with `services.avahi` in `network.nix` — no conflict.
- `boot.supportedFilesystems = [ "nfs" ]` is a list that merges additively with any existing entries.
- `services.samba-wsdd` is a new top-level service with no existing definitions — no conflict.

---

## 7. Risks and Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| WSDD opens firewall ports (TCP 5357, UDP 3702) on display roles | Low | These are standard WSD ports. Only accessible on the local network. `openFirewall = true` is the documented NixOS approach. Firewall still denies all other inbound traffic. |
| Avahi `publish.enable` advertises this machine on the network | Low | This is standard behavior on Fedora/Ubuntu GNOME. Only publishes hostname and enabled services. Does not expose file shares unless a Samba server is explicitly configured. |
| `services.samba-wsdd` may log warnings if `services.samba.enable` is not set | Low | WSDD functions independently as a discovery responder even without a local Samba server. It will still discover remote WSD hosts. If warnings appear, they are cosmetic and do not affect functionality. |
| NFS kernel module increases kernel surface | Very Low | NFS client module is loaded by every major Linux distribution by default. No NFS server is started; only client-side support is enabled. |
| `boot.supportedFilesystems = ["nfs"]` may slightly increase boot time | Very Low | The NFS kernel module is small and loads quickly. The `nfs-utils` package is only ~2 MB. |
| Headless-server role accidentally gets discovery features | None | `network-desktop.nix` is NOT imported by `configuration-headless-server.nix`. Verified in codebase analysis. |

---

## 8. Research Sources

1. **NixOS Wiki — Samba**: `services.samba-wsdd`, Avahi publish configuration for share discovery, GVFS browsing section. URL: https://wiki.nixos.org/wiki/Samba
2. **NixOS Wiki — GNOME**: GNOME module configuration, `services.desktopManager.gnome.enable` auto-enabling GVfs. URL: https://wiki.nixos.org/wiki/GNOME
3. **NixOS Wiki — NFS**: Client configuration with `boot.supportedFilesystems = ["nfs"]`, nfs-utils. URL: https://wiki.nixos.org/wiki/NFS
4. **Arch Wiki — GNOME/Files**: GVfs network share backends (SMB, NFS, WebDAV), `gvfs-wsdd` for WSD support, network share discovery requirements. URL: https://wiki.archlinux.org/title/GNOME/Files
5. **Arch Wiki — Avahi**: mDNS service discovery, `publish.enable`/`publish.userServices`, firewall requirements, NFS/Samba service advertisement. URL: https://wiki.archlinux.org/title/Avahi
6. **NixOS Options Search — `services.gvfs`**: Confirmed `services.gvfs.enable` and `services.gvfs.package` options. URL: https://search.nixos.org/options?query=services.gvfs

---

## 9. Files to Modify

| File | Action | Description |
|------|--------|-------------|
| `modules/network-desktop.nix` | **Modify** | Add Avahi publish, WSDD service, and NFS client support |

No new files created. No import list changes in any `configuration-*.nix`.

---

## 10. Verification Checklist

After implementation, the following should be verifiable:

- [ ] `nix flake check` passes
- [ ] Dry-build succeeds for all GNOME roles (desktop, htpc, server, stateless)
- [ ] `systemctl status wsdd` shows active on a deployed GNOME role
- [ ] `systemctl status avahi-daemon` shows publishing enabled
- [ ] Nautilus → sidebar → "Network" shows discovered SMB/NFS hosts on the LAN
- [ ] `avahi-browse -a` shows `_smb._tcp` and other services from LAN hosts
- [ ] Headless-server build does NOT include WSDD or NFS client support
- [ ] No `lib.mkIf` guards were added (architecture compliance)
