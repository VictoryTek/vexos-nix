# NAS GUI Dashboard for vexos-nix — Comprehensive Research

**Status:** Phase 1 — Research  
**Author:** Research Subagent  
**Date:** 2026-05-09  

---

## 1. Executive Summary

The user wants a **full NAS solution with a web GUI dashboard** — comparable to TrueNAS, OpenMediaVault, or NASty — on NixOS with ZFS. This document exhaustively evaluates every viable option.

**Bottom line:** There is **no single product** that gives a true TrueNAS/OMV-like experience natively on NixOS. The closest achievable result is a **Cockpit + 45Drives plugin stack** (cockpit-file-sharing + cockpit-zfs + cockpit-navigator + cockpit-identities), which covers ~70-80% of what TrueNAS offers from a web UI perspective. Everything else is either impossible on NixOS, Docker-only with severe ZFS limitations, or fundamentally incompatible.

---

## 2. Comparison Table — All Options

| # | Option | GUI Completeness (1-5) | ZFS Support | NixOS Compatibility | Maintenance Status | Integration Effort | Architecture Conflicts |
|---|--------|----------------------|-------------|--------------------|--------------------|-------------------|----------------------|
| 1 | **OpenMediaVault (OMV)** | 5 | Plugin (openmediavault-zfs) | ❌ Impossible natively; Docker = broken (see §3.1) | Active (73 contributors, daily commits) | N/A — cannot run | Wants full OS control |
| 2 | **TrueNAS SCALE/CORE** | 5 | Native (core feature) | ❌ Full appliance OS only; VM only | Active (iXsystems, commercial) | N/A — VM or separate box | Separate OS entirely |
| 3 | **Cockpit + 45Drives full stack** | 4 | Native via cockpit-zfs | ✅ `pkgs.cockpit` in nixpkgs; plugins need custom packaging | Active (see §3.3) | Medium — best option | Cockpit already in vexos |
| 4 | **Filestash** | 2 (file browser only) | N/A (storage-agnostic client) | Docker only, not in nixpkgs | Active (14.2k stars, 74 contributors) | Low but limited value | None, but not a NAS manager |
| 5 | **Nextcloud** | 2 (cloud storage, not NAS) | N/A (app-level) | ✅ `services.nextcloud` in nixpkgs | Active, well-maintained | Low (already in vexos) | Not a NAS solution |
| 6 | **CasaOS** | 3 | No native ZFS support | ❌ Debian/Ubuntu install script only, not in nixpkgs | Stale (last commit 9mo ago, v0.4.15) | High — mutable-config | Wants systemd ownership |
| 7 | **Cosmos-Server** | 3 | Storage manager (basic disk ops) | Docker only (--network host, --privileged) | Active (v0.22.18, 5.9k stars) | Medium-High | Conflicts with Caddy, Authelia (own reverse proxy + auth) |
| 8 | **NASty** | 4 | ❌ bcachefs only, structural | ❌ Own nixos-unstable distribution | v0.0.6, 2 contributors | Impossible — fork required | Total conflict (see existing spec §3) |
| 9 | **DIY: Cockpit + plugins + Samba/NFS** | 4 | Native | ✅ Best fit | Depends on components | Medium — RECOMMENDED | Already aligned |
| 10 | **OMV in NixOS container/VM** | 5 (inside VM) | ❌ ZFS passthrough problematic | Possible but complex (microvm/QEMU) | N/A | Very High | Separate OS in VM, management overhead |
| 11 | **Webmin** | 3 | Basic (module exists) | ❌ Not in nixpkgs (only python xmlrpc client) | Aging, mutable-config model | High — poor NixOS fit | Fights NixOS declarative model |
| 12 | **Houston by 45Drives** | N/A | N/A | N/A | ❌ `houston-ui` repo returns 404 | N/A | Houston IS the Cockpit plugins (see §3.12) |

---

## 3. Detailed Analysis Per Option

### 3.1 OpenMediaVault (OMV)

**What it is:** A complete Debian-based NAS operating system with a web management panel. PHP+SaltStack+TypeScript architecture. 6.7k GitHub stars, 73 contributors.

**Can it run on NixOS natively?** **No.** The OMV README explicitly states: _"openmediavault expects to have full, exclusive control over OS configuration and cannot be used within a container. Also, no graphical desktop user interface can be installed in parallel."_ It is deeply coupled to Debian's `dpkg`, `apt`, SaltStack states, and `/etc/default/*` configuration. It cannot be decomposed into a standalone service.

**Can it run in Docker on NixOS?** Technically, community Docker images exist (ikogan/openmediavault — 10K pulls, 8 years old; most others abandoned). However:
- OMV wants to manage system services (Samba, NFS, SSH, cron) — in Docker these are sandboxed and can't manage the host
- ZFS passthrough from Docker to OMV is unsupported — OMV's openmediavault-zfs plugin expects to run `zpool`/`zfs` commands on the host kernel, which requires `--privileged` and host device access. This creates a fragile, unsupported configuration
- The Docker images are all community-maintained, abandoned (most are 3-8 years old), and OMV upstream explicitly rejects container deployment

**ZFS support:** Via the `openmediavault-zfs` plugin (not part of core OMV). Requires ZFS kernel modules on the host.

**Verdict: REJECT.** OMV is fundamentally a competing operating system, not a composable service.

### 3.2 TrueNAS SCALE / TrueNAS CORE

**What it is:** The gold standard of NAS operating systems. CORE is FreeBSD-based; SCALE is Debian-based. Both are complete OS images from iXsystems.

**Can any component run standalone on NixOS?** **No.** TrueNAS is a monolithic appliance. The middleware layer (`middlewared`) is deeply coupled to its own OS stack. There is no TrueNAS library, package, or module that can be extracted.

**Can it run as a VM on NixOS?** Yes — you can run TrueNAS SCALE in a QEMU/KVM VM and pass through disks via PCI passthrough or virtio. However:
- You lose ZFS integration with the NixOS host (the VM owns the disks)
- Double overhead: TrueNAS VM + NixOS host both running
- NixOS becomes just a hypervisor — defeats the purpose of a unified config
- IOMMU/VT-d required for HBA passthrough

**Verdict: REJECT for integration.** Valid only as a "separate NAS box" approach. If the user wants the full TrueNAS experience, running TrueNAS on dedicated hardware is honestly the best path — but that's not what was asked for.

### 3.3 Cockpit + 45Drives Full Stack (RECOMMENDED — PRIMARY)

This is the most viable option. 45Drives (a Canadian storage company) develops a suite of Cockpit plugins that together create a NAS management dashboard:

#### Component Inventory

| Plugin | GitHub | Stars | Last Commit | Releases | nixpkgs Package | Purpose |
|--------|--------|-------|-------------|----------|-----------------|---------|
| **cockpit-file-sharing** | 45Drives/cockpit-file-sharing | 935 | 3 weeks ago (v4.5.6) | 86 | ❌ NOT in nixpkgs | Samba + NFS + iSCSI + S3 share management |
| **cockpit-zfs** (NEW) | 45Drives/cockpit-zfs | 106 | 1 week ago (v1.2.26) | 67 | ❌ NOT in nixpkgs | ZFS pool, dataset, snapshot, disk management |
| **cockpit-navigator** | 45Drives/cockpit-navigator | 723 | 6 months ago (v0.5.12) | 24 | ❌ NOT in nixpkgs | Web-based file browser |
| **cockpit-identities** | 45Drives/cockpit-identities | 237 | 3 years ago (v0.1.12) | 8 | ❌ NOT in nixpkgs | User/group + Samba password management |
| **cockpit** (base) | cockpit-project/cockpit | — | Active | — | ✅ `pkgs.cockpit` v351 | Base web console |

**CRITICAL CORRECTION:** The existing NAS spec (`.github/docs/subagent_docs/nas_service_spec.md`) states that `pkgs.cockpit-file-sharing`, `pkgs.cockpit-navigator`, and `pkgs.cockpit-identities` are "already in nixpkgs 25.11." **This is WRONG.** My search of `search.nixos.org` confirms:
- `cockpit-file-sharing` → **No packages found!**
- `cockpit-navigator` → **No packages found!**
- `cockpit-identities` → **No packages found!**
- `cockpit` (base) → ✅ Found, v351

Only the base `cockpit` package is in nixpkgs. The 45Drives plugins would need to be **packaged as custom derivations** in the vexos-nix flake or as overlays.

#### cockpit-zfs (NEW — replaces cockpit-zfs-manager)

**Key discovery:** The old `cockpit-zfs-manager` (optimans/cockpit-zfs-manager) is **EOL since 2021** (archived). The 45Drives fork (`45Drives/cockpit-zfs-manager`) was **archived on March 10, 2026** with a message redirecting to the **NEW** `45Drives/cockpit-zfs` repository.

`cockpit-zfs` is actively developed (last commit: 1 week ago, v1.2.26, 67 releases, 7 contributors). It provides:
- ZFS pool management (create, import, export, destroy)
- VDev information and disk management
- Dataset/filesystem operations
- Snapshot management (create, rollback, destroy, clone)
- Scrub/resilver status monitoring
- Email notifications via cockpit-alerts
- Uses `python3-libzfs` bindings with CLI fallback

**Runtime dependencies:** python3, python3-libzfs (optional but recommended), python3-dateutil, sqlite3, jq, msmtp. Also NOT in nixpkgs — would need custom packaging including the `python3-libzfs` bindings.

#### What the Cockpit Stack Covers

With all four plugins + base Cockpit, you get:

| NAS Feature | Coverage | Quality |
|-------------|----------|---------|
| **Create/manage Samba shares** | ✅ cockpit-file-sharing | Excellent — full smb.conf registry, global settings, per-share config, ZFS shadow_copy2 integration, Windows ACL support |
| **Create/manage NFS exports** | ✅ cockpit-file-sharing | Good — graphical /etc/exports editing, per-client options |
| **iSCSI targets** | ✅ cockpit-file-sharing v4.5+ | New in recent versions |
| **S3 buckets** (MinIO/RustFS/Ceph/Garage) | ✅ cockpit-file-sharing v4.5+ | Backend-specific management |
| **Browse files on server** | ✅ cockpit-navigator | Good — upload, download, rename, permissions, symlinks |
| **User/group management** | ✅ cockpit-identities | Good — create/delete users, manage groups, Samba passwords, SSH keys, login history |
| **ZFS pool management** | ✅ cockpit-zfs | Good — create pools, manage VDevs, view disk info |
| **ZFS snapshots** | ✅ cockpit-zfs | Good — create, rollback, clone, destroy |
| **ZFS dataset management** | ✅ cockpit-zfs | Good — create, configure properties |
| **Disk health (SMART)** | ✅ Scrutiny (already in vexos) | Excellent — already configured as `vexos.server.scrutiny` |
| **System monitoring** | ✅ Cockpit base | Good — CPU, memory, network, disk I/O, logs |
| **Docker/container management** | ✅ Cockpit base (podman) | Basic — Portainer is better (already in vexos) |
| **Backup/replication** | ❌ | Not covered — would need sanoid/syncoid or manual ZFS send/recv |
| **Notification/alerting** | Partial via cockpit-zfs + Scrutiny | Scrutiny handles SMART alerts; cockpit-zfs handles ZFS alerts |

#### Integration Approach

Since the 45Drives plugins are NOT in nixpkgs, there are two paths:

**Option A: Custom Nix derivations (RECOMMENDED)**
Package each Cockpit plugin as a Nix derivation that builds from source or fetches the pre-built release archive and installs to `/share/cockpit/<plugin>/`. Cockpit auto-discovers plugins in the Nix profile path. This is the clean NixOS-native approach but requires writing ~4 derivation files.

**Option B: Fetch pre-built, install via activation script**
Download the `.deb`/`.rpm` or generic archives at build time and extract the Cockpit plugin directories. Less clean but faster to prototype.

**cockpit-zfs complications:** Requires `python3-libzfs` (Python bindings for libzfs), which is also not in nixpkgs and requires building against ZFS development headers. This is the hardest part of the integration — building C extension modules against `pkgs.zfs.dev` in a Nix derivation.

### 3.4 Filestash

**What it is:** A storage-agnostic file management platform. Supports FTP, SFTP, S3, SMB, WebDAV, and ~20 more backends via plugins. 14.2k stars, 74 contributors, active development (commits yesterday).

**Is it a NAS manager?** **No.** It's a file browser/manager. It does NOT:
- Create or manage Samba/NFS shares
- Manage ZFS pools or datasets
- Manage users or permissions at the OS level
- Monitor disk health

It IS a nice web-based file explorer that can connect to existing shares. Think of it as a web-based alternative to Nautilus/Finder.

**NixOS availability:** Not in nixpkgs. Docker image available.

**Verdict: NOT a NAS solution.** Could complement a NAS setup as a web file browser (similar role to cockpit-navigator), but it doesn't manage anything. Also, Nextcloud already fills the "web file access" role if enabled.

### 3.5 Nextcloud

**What it is:** Self-hosted cloud storage and collaboration platform. Already in vexos as `modules/server/nextcloud.nix`.

**NAS relevance:** Nextcloud has "External storage" support that can mount existing SMB/NFS shares into the Nextcloud file tree. But it's fundamentally a cloud-storage and collaboration platform, not a NAS management tool. It cannot:
- Create or manage Samba/NFS shares
- Manage ZFS
- Manage OS-level users or disks

**Verdict: Complementary, not primary.** Already available in vexos. Not a NAS dashboard.

### 3.6 CasaOS

**What it is:** A lightweight personal cloud OS from IceWhaleTech (ZimaBoard maker). Web UI for Docker app management, file management, disk management. 33.8k stars, 24 contributors.

**NixOS compatibility:** **Poor.**
- Installation is via `wget | bash` install script targeting Debian/Ubuntu only
- Not in nixpkgs (confirmed: `search.nixos.org` returns "No packages found!")
- Written in Go, could theoretically be packaged, but CasaOS is a system manager that wants to control systemd units, modify `/etc/fstab`, manage Docker, and handle networking
- Last release: v0.4.15, December 2024 — **9 months without updates**

**ZFS support:** CasaOS's disk management is basic — it handles ext4/NTFS/FAT32 mounts. No ZFS pool management, no ZFS snapshots, no ZFS-aware features.

**Verdict: REJECT.** Not a NAS management tool. More of a lightweight Docker app launcher with a file browser. Stale development. No ZFS support. Installation model incompatible with NixOS.

### 3.7 Cosmos-Server

**What it is:** Self-hosted home server platform with reverse proxy, auth, container management, storage management, VPN, monitoring. 5.9k stars, 19 contributors, very active (v0.22.18, commits 3 days ago).

**NAS-relevant features:**
- Storage Manager: disk management including Parity Disks and MergerFS
- Network Storages: NFS/FTP sharing based on RClone, managed from UI
- File browser with SmartShield protection

**NixOS compatibility:** Docker only. Installation requires:
```
docker run --network host --privileged -v /var/run/docker.sock:/var/run/docker.sock -v /:/mnt/host ...
```
The `--privileged`, `--network host`, and `-v /:/mnt/host` requirements are aggressive. The README explicitly says: _"DO NOT USE UNRAID TEMPLATES, CASAOS OR PORTAINER STACKS TO INSTALL COSMOS. IT WILL NOT WORK PROPERLY."_

**Critical conflicts with vexos:**
- Cosmos IS a reverse proxy (conflicts with Caddy)
- Cosmos IS an auth server (conflicts with Authelia)
- Cosmos wants to own port 80/443
- Cosmos wants to manage Docker containers (conflicts with Portainer)
- License: Apache 2.0 with **Commons Clause** — cannot be sold or offered as a service

**ZFS support:** Basic disk management via Storage Manager; not ZFS-native, no pool/dataset/snapshot management.

**Verdict: REJECT.** Massively conflicts with existing vexos architecture. Would replace Caddy + Authelia + Portainer rather than complement them. Not ZFS-aware. Commons Clause license is restrictive.

### 3.8 NASty

Already thoroughly rejected in the existing NAS spec (`.github/docs/subagent_docs/nas_service_spec.md` §3). Summary:
- bcachefs structural coupling (no ZFS support possible without forking)
- v0.0.6, 2 contributors, "not production"
- nixos-unstable channel mismatch
- Would conflict with NetworkManager, ACME, auth layer, kernel pinning

**Verdict: REJECTED (confirmed).**

### 3.9 DIY: Cockpit + All Plugins + Samba/NFS (RECOMMENDED — essentially §3.3)

This IS option §3.3, explicitly spelled out. The "DIY" framing is important because there is no single "install NAS dashboard" package. You are assembling:

1. **Cockpit base** (nixpkgs) — system monitoring, terminal, logs
2. **cockpit-file-sharing** (custom derivation) — Samba + NFS share management GUI
3. **cockpit-zfs** (custom derivation) — ZFS pool/dataset/snapshot management GUI
4. **cockpit-navigator** (custom derivation) — web file browser
5. **cockpit-identities** (custom derivation) — user/group + Samba password management
6. **Scrutiny** (already in vexos) — SMART disk health monitoring
7. **NixOS declarative Samba/NFS** (the existing nas.nix spec) — the actual protocol daemons

**How complete is this vs TrueNAS?**

| Feature Area | TrueNAS SCALE | Cockpit + 45Drives Stack | Gap |
|-------------|---------------|--------------------------|-----|
| Share management (SMB/NFS) | ✅ Full GUI | ✅ cockpit-file-sharing | Comparable |
| ZFS management | ✅ Full GUI | ✅ cockpit-zfs | Comparable for basic ops; TrueNAS is more polished |
| Disk health | ✅ Built-in | ✅ Scrutiny (separate UI) | Scrutiny is arguably better |
| File browser | ✅ Built-in | ✅ cockpit-navigator | Comparable |
| User management | ✅ Built-in | ✅ cockpit-identities | Comparable |
| Snapshots + auto-snapshot | ✅ Full GUI + scheduler | ⚠️ cockpit-zfs manual; no scheduler | Gap — need sanoid for auto-snapshots |
| Replication (send/recv) | ✅ Full GUI | ❌ Manual only | Significant gap |
| Backup management | ✅ Built-in | ❌ Separate tool needed | Gap |
| Alerting/notifications | ✅ Built-in | ⚠️ Scrutiny + cockpit-zfs email | Partial |
| VM/container management | ✅ Built-in | ⚠️ Cockpit+Portainer | Different tools |
| Plugin/app ecosystem | ✅ TrueNAS Charts/Apps | N/A (NixOS modules) | Different paradigm |
| Unified auth | ✅ Single login | ✅ Cockpit auth (+ Caddy/Authelia) | Comparable |
| Mobile app | ✅ TrueNAS app | ❌ | Gap |

**Honest assessment: ~70-80% of TrueNAS functionality.** The main gaps are automated snapshots/replication (solvable with sanoid/syncoid but no GUI) and the polish of a purpose-built NAS OS.

### 3.10 OMV in NixOS Container/VM

**Approach:** Run OpenMediaVault inside a NixOS container (`nixos-container`) or microvm.

**Problems:**
- OMV needs systemd as PID 1 with full control — works in a NixOS container but with heavy overhead
- ZFS passthrough: OMV inside a container cannot manage ZFS pools on the host. The ZFS kernel module runs on the host; the container would need `/dev/zfs` passthrough plus ZFS userland tools, and OMV's openmediavault-zfs plugin would need to believe it's running on bare metal
- Two package managers: OMV inside the container uses apt/dpkg; outside is Nix. Updates, security patches, and state management become a nightmare
- Networking: OMV wants to manage the network stack; container networking adds complexity

**In a microvm/QEMU VM:**
- Possible with disk passthrough (HBA passthrough or individual disks)
- But then NixOS host can't see the ZFS pools — the VM owns them
- You're essentially running TrueNAS SCALE at that point; might as well use actual TrueNAS

**Verdict: REJECT.** Worst of both worlds. If you want OMV, run it on bare metal or a dedicated VM, not awkwardly nested inside NixOS.

### 3.11 Webmin

**What it is:** Classic (1997-era) web-based system administration tool. Perl-based, manages configuration files directly via the web UI.

**NixOS availability:** **Not in nixpkgs** as a standalone package. Only `python3-webmin-xmlrpc` (a Python client library) exists. The NixOS wiki page for Webmin returns 404.

**Why it's a poor fit for NixOS:**
- Webmin directly edits `/etc/samba/smb.conf`, `/etc/exports`, `/etc/fstab`, etc. — this is the antithesis of NixOS's declarative model where these files are generated from Nix expressions
- Any changes Webmin makes would be overwritten on the next `nixos-rebuild`
- The Webmin Samba module is decent but outdated compared to cockpit-file-sharing
- ZFS support exists (Webmin ZFS module) but is basic

**Verdict: REJECT.** Fundamentally incompatible with NixOS's declarative configuration model.

### 3.12 Houston by 45Drives

**Investigation result:** "Houston" is 45Drives' **branding** for their Cockpit plugin collection, not a separate standalone product. The `houston-ui` GitHub repo returns **404** (deleted or never existed publicly). The term "Houston UI" appears in the cockpit-identities README (_"User and group management plugin for Houston UI (Cockpit)"_).

The Cockpit plugins (cockpit-file-sharing, cockpit-navigator, cockpit-identities, cockpit-zfs) collectively **are** Houston. They share a common library submodule (`houston-common`).

**Verdict: Already covered by §3.3. Not a separate product.**

---

## 4. Top 3 Recommendations

### Rank 1: Cockpit + 45Drives Plugin Stack (DIY Assembly)

**Deployment approach:** Native NixOS with custom Nix derivations for the 45Drives plugins.

**What the user experience looks like:**
- Open `https://server:9090` in browser → Cockpit login (PAM auth, or via Caddy+Authelia)
- Left sidebar shows: System, ZFS, File Sharing, Navigator, Identities, plus standard Cockpit pages (Terminal, Logs, Networking, Storage)
- ZFS page: view all pools, datasets, snapshots; create new pools; take snapshots; view scrub status
- File Sharing page: create/edit/delete Samba shares and NFS exports from a GUI with one-click configs for MacOS optimization, Windows ACLs, shadow copies (ZFS snapshots visible as Windows Previous Versions)
- Navigator page: browse the server filesystem, upload/download files, set permissions
- Identities page: create OS users, manage groups, set Samba passwords, manage SSH keys

**What's managed via GUI vs Nix config:**
- **GUI (runtime):** Share creation/modification, user Samba passwords, snapshot creation, file browsing, ZFS dataset properties
- **Nix config (declarative):** Cockpit service enablement, plugin installation, Samba global defaults (min protocol, workgroup), NFS server enablement, ZFS module/kernel config, firewall rules
- This is a **hybrid model** — the Nix config sets up the infrastructure; the GUI manages day-to-day operations. This matches how Cockpit is designed to work.

**Integration complexity:** **MEDIUM-HIGH**
- Need to write 4+ custom Nix derivations for the 45Drives plugins
- `cockpit-zfs` requires `python3-libzfs` C extension bindings — hardest part
- Each plugin is a Vue.js/TypeScript frontend + Python/Shell backend that expects to write to Cockpit's plugin directory
- Estimated: 2-4 new files in the flake for derivations, modifications to `modules/server/cockpit.nix`

**Risks:**
- 45Drives plugins are not in nixpkgs — maintenance burden on vexos-nix to track upstream releases
- `python3-libzfs` may have build issues with NixOS's ZFS packaging
- cockpit-file-sharing mutates Samba configuration at runtime (via `net conf` registry) — this is inherently at odds with NixOS's declarative `services.samba.settings`. **The file-sharing plugin CANNOT be used alongside NixOS's declarative Samba config for the same shares.** You'd need to choose: GUI-managed shares (via Samba registry) OR Nix-managed shares (via `services.samba.settings`). Both can coexist if the Nix config only sets globals and the GUI manages individual shares via the registry.

### Rank 2: Cockpit (base only) + Declarative Samba/NFS + Scrutiny

**Deployment approach:** Use what's already in nixpkgs — no custom derivations.

This is essentially the existing NAS spec (`nas_service_spec.md`) without the 45Drives plugins. You get:
- Cockpit base for system monitoring + terminal
- Declarative Samba/NFS shares via the `vexos.server.nas` module
- Scrutiny for disk health

**What's missing vs Rank 1:**
- No GUI share management — shares are code in Nix
- No GUI ZFS management — `zpool` and `zfs` CLI only
- No web file browser (Cockpit base doesn't include one)
- No GUI user/group management (use CLI or Cockpit's built-in basic account page)

**Integration complexity:** **LOW** — everything is already in nixpkgs.

**Verdict:** This is the "safe" option. Works today, no custom packaging. But it's not a "NAS dashboard" — it's declarative NAS config with a system monitoring web UI.

### Rank 3: Separate TrueNAS VM/Box + NFS/SMB Mounts

**Deployment approach:** Run TrueNAS SCALE on separate hardware (or a VM with HBA passthrough) and mount its shares on the NixOS server.

**What the user experience looks like:**
- Full TrueNAS web UI at its own IP address — the gold standard NAS experience
- NixOS server mounts TrueNAS shares via NFS/SMB using `fileSystems` or autofs
- Media services (Jellyfin, *arr, etc.) on NixOS point to the mounted paths

**Pros:** You get the actual TrueNAS experience with zero compromises.
**Cons:** 
- Two systems to manage
- If using a VM: IOMMU/VT-d required, HBA passthrough config, more resource overhead
- If separate hardware: additional cost, power, space
- Does not satisfy the "unified NixOS config" desire

**Integration complexity:** **LOW** for the mount side (just `fileSystems.*` entries), **HIGH** for VM setup with passthrough.

---

## 5. Honest Assessment

### Is there ANY option that gives a true TrueNAS-like experience on NixOS?

**No.** Not today. Here's why:

1. **TrueNAS and OMV are operating systems, not applications.** They are designed to own the entire machine. You cannot extract their management layer and bolt it onto NixOS any more than you can extract Windows Explorer and run it on Linux.

2. **NixOS's declarative model conflicts with NAS GUIs.** NAS dashboards work by modifying configuration files at runtime (`smb.conf`, `/etc/exports`, ZFS properties). NixOS generates these files from Nix expressions and overwrites runtime changes on rebuild. The two paradigms fundamentally conflict.

3. **The Cockpit + 45Drives approach is the best compromise** because Cockpit is explicitly designed to work alongside system management tools (it reads system state; file-sharing uses Samba's registry mode which bypasses `/etc/samba/smb.conf`; cockpit-zfs calls ZFS CLI tools which modify pool-level state outside NixOS's scope).

### Packaging Reality Check

The biggest obstacle to the Cockpit + 45Drives path is **packaging**. None of the 45Drives plugins are in nixpkgs. Packaging them requires:

1. **cockpit-navigator** (easiest): Pure JavaScript/HTML, just copy files to `/share/cockpit/navigator/`
2. **cockpit-identities** (easy): Vue.js pre-built, just copy files
3. **cockpit-file-sharing** (medium): Vue.js + TypeScript frontend, Python/Shell backend scripts, requires `samba` and `nfs-utils` at runtime
4. **cockpit-zfs** (hard): Vue.js frontend + Python backend requiring `python3-libzfs` (C extension binding to libzfs). Building `python3-libzfs` against NixOS's ZFS package is the most challenging part

If the user is willing to accept the packaging effort (or accept that cockpit-zfs is optional if `python3-libzfs` proves too difficult), the Cockpit stack is the clear winner.

### Recommendation

**For a pragmatic NAS dashboard today:** Start with Rank 2 (declarative Samba/NFS + Cockpit base + Scrutiny). This gives you working NAS shares with system monitoring, all from nixpkgs. Then incrementally add 45Drives plugins as custom derivations, starting with cockpit-navigator (easiest) and cockpit-file-sharing.

**For maximum GUI coverage:** Commit to Rank 1 — package all four 45Drives plugins. Accept that this creates a maintenance surface (tracking upstream releases, rebuilding on ZFS version bumps). The result will be ~70-80% of TrueNAS's web management capability.

**If nothing less than TrueNAS will do:** Run TrueNAS on a separate box (Rank 3). Accept the two-system management overhead. Mount its shares on the NixOS server.

---

## 6. Source Inventory

| # | Source | Type | Key Finding |
|---|--------|------|-------------|
| 1 | github.com/45Drives/cockpit-file-sharing | GitHub repo | v4.5.6, 935 stars, 13 contributors, active (3 weeks ago). Samba + NFS + iSCSI + S3 GUI for Cockpit. |
| 2 | github.com/45Drives/cockpit-zfs | GitHub repo | v1.2.26, 106 stars, 7 contributors, actively maintained (1 week ago). NEW replacement for archived cockpit-zfs-manager. |
| 3 | github.com/45Drives/cockpit-navigator | GitHub repo | v0.5.12, 723 stars, 8 contributors, last release Sep 2025. Web file browser for Cockpit. |
| 4 | github.com/45Drives/cockpit-identities | GitHub repo | v0.1.12, 237 stars, 2 contributors, last release May 2023. User/group management. Stable but aging. |
| 5 | github.com/45Drives/cockpit-zfs-manager | GitHub repo (ARCHIVED) | Archived March 2026. Redirects to cockpit-zfs. Previous spec referenced this — now superseded. |
| 6 | github.com/optimans/cockpit-zfs-manager | GitHub repo (ARCHIVED) | Original cockpit-zfs-manager, EOL since July 2021. |
| 7 | github.com/openmediavault/openmediavault | GitHub repo | 6.7k stars, 73 contributors. Explicitly states cannot run in containers. Debian-only. |
| 8 | github.com/IceWhaleTech/CasaOS | GitHub repo | 33.8k stars but stale (last commit 9mo ago). Debian/Ubuntu only install. No ZFS support. |
| 9 | github.com/azukaar/Cosmos-Server | GitHub repo | 5.9k stars, v0.22.18, active. Docker-only. Conflicts with Caddy/Authelia. Apache-2.0 + Commons Clause. |
| 10 | github.com/mickael-kerjean/filestash | GitHub repo | 14.2k stars, 74 contributors, active. File browser, not NAS manager. Docker only. |
| 11 | search.nixos.org/packages | NixOS package search | Confirmed: cockpit (v351) in nixpkgs. cockpit-file-sharing, cockpit-navigator, cockpit-identities, casaos, openmediavault, filestash, webmin — ALL NOT in nixpkgs. |
| 12 | github.com/AnalogJ/scrutiny | GitHub repo | 7.7k stars, v0.9.2, active. SMART monitoring. Already in vexos as `modules/server/scrutiny.nix`. |
| 13 | discourse.nixos.org | NixOS forum | Minimal NAS-specific discussion. One relevant thread on NixOS as hypervisor notes TrueNAS SCALE is "inflexible w.r.t. ZFS" and explores NixOS as alternative. |
| 14 | hub.docker.com | Docker Hub | OMV Docker images exist (ikogan/openmediavault, 10K pulls) but are community-maintained, 8 years old, and unsupported by OMV upstream. |
| 15 | .github/docs/subagent_docs/nas_service_spec.md | Existing vexos spec | Previous NAS research. Contains INCORRECT claim about 45Drives plugins being in nixpkgs. Cockpit plugin approach is sound but packaging assumptions are wrong. |

---

## 7. Corrections to Existing NAS Spec

The existing `nas_service_spec.md` contains the following error that must be corrected:

**Section 4, Alternatives Comparison table:** States "Cockpit + 45Drives modules — NixOS-native: Yes (`pkgs.cockpit*` in nixpkgs)"

**Section 7, Dependencies table:** States:
- "`pkgs.cockpit-file-sharing` — nixpkgs (45Drives, GPL-3.0) — nixpkgs package — Context7 not applicable. Verified present in nixos-25.11."
- "`pkgs.cockpit-navigator` — nixpkgs (45Drives, GPL-3.0) — Same."
- "`pkgs.cockpit-identities` — nixpkgs (45Drives, GPL-3.0) — Same."

**Reality:** None of these three packages exist in nixpkgs. Only `pkgs.cockpit` (the base Cockpit package, v351) is available. The 45Drives plugins would need custom packaging.

This changes the implementation complexity significantly: the cockpit.nix modification from the existing spec (`environment.systemPackages = with pkgs; [ cockpit-file-sharing cockpit-navigator cockpit-identities ]`) **will not evaluate** because those packages don't exist.

---

## 8. Integration with Existing vexos-nix Architecture

The Cockpit + 45Drives approach integrates well with the existing stack:

| Existing Module | Relationship | Conflict? |
|----------------|--------------|-----------|
| `modules/server/cockpit.nix` | Extends with plugin packages | No — additive |
| `modules/server/nas.nix` (proposed) | Samba/NFS daemon config | Partial — GUI share management via cockpit-file-sharing uses Samba registry, which is separate from Nix-declarative shares. Can coexist if Nix config sets globals only. |
| `modules/server/caddy.nix` | Reverse-proxy for Cockpit UI | No conflict — Cockpit on :9090, Caddy on :80/:443 |
| `modules/server/authelia.nix` | Auth for Cockpit via Caddy forward_auth | No conflict — standard pattern |
| `modules/server/scrutiny.nix` | Disk health monitoring | Complementary — Scrutiny covers SMART; cockpit-zfs covers ZFS |
| `modules/zfs-server.nix` | ZFS kernel/userland | Complementary — cockpit-zfs uses the ZFS tools installed here |
| `modules/server/docker.nix` | Not needed for Cockpit plugins | No conflict |

---

## 9. Summary

| Approach | Feasibility | GUI Quality | ZFS Quality | Effort | Risk |
|----------|-------------|-------------|-------------|--------|------|
| **Cockpit + 45Drives (custom pkgs)** | High | 4/5 | 4/5 | Medium-High | Medium (packaging maintenance) |
| **Declarative NAS + Cockpit base** | High | 2/5 | N/A (CLI) | Low | Low |
| **TrueNAS separate box** | High | 5/5 | 5/5 | Low (mount side) | Low |
| **OMV in any form on NixOS** | Very Low | N/A | N/A | N/A | N/A |
| **CasaOS/Cosmos/Filestash** | Low | 2-3/5 | 0-1/5 | High | High |
| **NASty** | Zero | N/A | N/A | N/A | N/A |
