# Analysis: Current NAS Config, the "Perfect Media Server" Recipe, and the Best Direction for a Flexible NAS Pool

**Type:** Research analysis (Phase 1 — no implementation performed)
**Question set:** (1) What does the current NAS config do, and what exactly is tied to `vexos.server.nas.enable`? (2) Re-assess the mergerfs+SnapRAID analysis. (3) Independent research + a recommended direction. (4) Do any of these methods broadcast the NAS on the network?
**Goal stated by operator:** A stable NAS that can pool *any kind of drive* for media *or* general storage, optionally serving Nextcloud, Proxmox, or working alongside the existing ZFS setup.
**Files reviewed:** `modules/server/nas.nix`, `modules/server/cockpit.nix`, `modules/network.nix`, `modules/network-desktop.nix`, `modules/zfs-server.nix`, `scripts/create-zfs-pool.sh`, `configuration-server.nix`, and the prior `pms_mergerfs_snapraid_conversion_analysis.md`.

---

## 1. What "just enable NAS" actually does today

`vexos.server.nas.enable = true` is a **thin UI umbrella**. It toggles nothing about storage. Concretely, from `modules/server/nas.nix`, it sets four `lib.mkDefault` flags:

- `vexos.server.cockpit.enable` — the Cockpit web console (port 9090)
- `vexos.server.cockpit.navigator.enable` — file browser plugin
- `vexos.server.cockpit.fileSharing.enable` — Samba (registry mode) + NFS server plugin
- `vexos.server.cockpit.identities.enable` — user/group/Samba-password management plugin

Everything that flows from that lives in `modules/server/cockpit.nix`:

- **Samba** in *registry mode* (`include = registry`; shares created by the plugin via `net conf`, not `smb.conf`), with `hosts allow` locked to localhost + RFC1918 + IPv6 ULA, `bind interfaces only = yes`, NetBIOS off by default.
- **NFS server**, exports managed by the plugin under `/etc/exports.d/`, `v4-minimal` firewall profile by default (only TCP 2049).
- **Firewall** ports opened only for the enabled services, optionally interface-scoped.

**Key architectural fact:** the NAS stack is **completely decoupled from the storage layer.** `nas.enable` never creates a pool, never picks a filesystem, never mounts anything. It shares *whatever is already mounted*. The storage layer is separate and imperative:

- `modules/zfs-server.nix` — loads ZFS, pins the LTS kernel, autoscrub/trim, hostId enforcement, disables disk swap.
- `scripts/create-zfs-pool.sh` (`just create-zfs-pool`) — interactively builds **one ZFS pool** (single/mirror/raidzN/raid10) for Proxmox VM storage, with an optional `tank/vm` child dataset.

So today the "NAS pool" and the "Proxmox pool" are the *same* ZFS pool, and there is no drive-pooling abstraction beyond what ZFS itself offers. That is the crux of the operator's problem: ZFS does **not** gracefully pool arbitrary mismatched drives (raidz caps at the smallest disk per vdev; mirrors need matched pairs; you cannot casually add one odd disk).

---

## 2. Re-assessment of the prior mergerfs+SnapRAID analysis

The prior doc's framing (Option A plain mergerfs+SnapRAID vs. Option B ZFS-backed mergerfs branches, with Proxmox staying on ZFS) is sound and still holds. **One material finding corrects it:**

> The prior doc (§3.2 step 3, §4 pitfall 4) states nixpkgs has **no native SnapRAID module**, only the package, and that config generation + timers would be hand-authored.

**This is outdated.** nixpkgs ships a full first-class module: `services.snapraid` with `dataDisks`, `parityFiles`, `contentFiles`, `exclude`, `extraConfig`, `touchBeforeSync`, and **built-in `sync.interval` / `scrub.interval` systemd timers** (plus `scrub.plan` / `scrub.olderThan`). `mergerfs` 2.41.1 is in nixpkgs as well.

Consequence: **Option A's implementation cost is much lower than the prior doc assumed.** SnapRAID is declarative NixOS options, not a from-scratch integration. This meaningfully shifts the recommendation toward Option A being a first-class, low-maintenance path rather than a bespoke one.

Everything else in the prior doc carries over: Samba/NFS (`cockpit.nix`), restic (`backup.nix`), and Scrutiny (`scrutiny.nix`) are filesystem-agnostic and need no change beyond pointing shares at the new mountpoint; data migration + physical disk separation from the Proxmox pool remain the real cost.

---

## 3. Does any of this broadcast the NAS on the network?

**Yes — and this is entirely independent of the storage/pooling choice.** Network advertisement is a function of the *sharing* layer (Samba/Avahi/wsdd), which does not care whether the bytes sit on ZFS, mergerfs, or ext4. Switching pooling backends changes nothing about discoverability. Current state:

| Mechanism | Where | What it broadcasts | Status |
|---|---|---|---|
| **WS-Discovery (wsdd)** | `services.samba-wsdd` in `network-desktop.nix` (imported by the server role) | Advertises the host to the Windows/Nautilus "Network" view over UDP 3702 (+ TCP 5357). `openFirewall = true`. | **Active — this is the primary "appears on the network" mechanism.** |
| **Avahi / mDNS host** | `services.avahi` (`network.nix`) + `services.avahi.publish` (`network-desktop.nix`) | `.local` name resolution, `_workstation._tcp`, host addresses, on UDP 5353. `openFirewall = true`. | **Active — host is resolvable/visible via mDNS.** |
| **Avahi `_smb._tcp` service record** | (none) | Would advertise *"this host offers an SMB share"* specifically to mDNS/Bonjour clients (macOS, GNOME). | **Gap — no `/etc/avahi/services/*.service` file is written.** The host is discoverable, but the SMB service itself is not mDNS-advertised. wsdd covers the Windows-style case; macOS/Bonjour clients would need this record to auto-surface the share. |
| **NetBIOS (nmbd)** | `services.samba.nmbd.enable = lib.mkDefault false` | Legacy broadcast browsing (UDP 137/138). | **Off by default** (reduced attack surface). |

Notes:
- `resolved` has `MulticastDNS = no` / `LLMNR = no` deliberately, so Avahi owns mDNS without racing systemd-resolved. Avahi excludes `tailscale0` so advertisements stay on the physical LAN.
- The stack is tuned for *client* discovery (finding other NAS devices in Nautilus) as much as advertising; both directions are wired.
- **If macOS/Bonjour auto-mount is desired**, the one missing piece is an Avahi `_smb._tcp` (and optionally `_device-info._tcp`) service file — a small, storage-agnostic addition, independent of any decision below.

**Bottom line:** the box already broadcasts itself (wsdd + Avahi host records). No storage direction you pick will change that. The only optional enhancement is an explicit SMB mDNS service record for Apple-ecosystem auto-discovery.

---

## 4. Independent research: matching the recipe to the *actual* requirements

The operator's goals are in tension, and no single pool optimizes all of them. Break the requirement down by workload, because each has a different "correct" filesystem:

| Workload | Access pattern | Right substrate | Why |
|---|---|---|---|
| **Bulk media** (movies, TV, photos-at-rest) | Large files, write-once/read-many, mixed drive sizes, grow one disk at a time | **mergerfs + SnapRAID** | Purpose-built for this. Any drive size/model, added individually, no rebalance. Each disk stays independently readable — pull it, read it on any Linux box. SnapRAID parity fits large static files perfectly. |
| **General / Nextcloud data** | Many small files, frequent rewrites, needs *realtime* redundancy | **ZFS mirror dataset** | SnapRAID parity only refreshes on schedule → anything written since the last sync is unprotected. Explicitly *not* recommended for churny data. ZFS gives synchronous redundancy + continuous checksums. |
| **Proxmox VM / zvol** | Random block I/O, constant rewrites | **ZFS (existing pool)** | Already the design. FUSE/mergerfs is unsuitable for VM block storage. Unchanged. |

The single most-emphasized requirement — *"pool from any kind of drive, for media or general storage"* — points squarely at **mergerfs** for the namespace/expansion layer, because ZFS structurally cannot do mixed-drive "add one at a time" pooling. The disagreement is only about the **redundancy** underneath mergerfs:

- **SnapRAID parity** (Option A): dedicate the largest disk(s) as parity; content disks can be any size. Cheapest capacity overhead, simplest mental model, now a first-class NixOS module. Trade-off: scheduled (not realtime) protection — fine for media, wrong for databases/Nextcloud live data.
- **ZFS single-disk branches** (a middle path): each drive is its own single-disk ZFS pool, mergerfs unions them. Gains per-disk bitrot *detection* and scrub; no repair without redundancy. Can still layer SnapRAID on top for cross-disk parity — this is the canonical "Perfect Media Server" stack (per-disk ZFS checksums + SnapRAID parity + mergerfs namespace).
- **ZFS mirror branches** (Option B as prior doc framed it): realtime redundancy per branch, but needs matched pairs and halves capacity — which directly contradicts the "any kind of drive" goal. Best reserved for the churny/Nextcloud tier, not the bulk media tier.

---

## 5. Recommended direction

**Adopt a tiered storage architecture; do not try to make one pool serve all three workloads.**

1. **Keep the existing ZFS pool for Proxmox VM/zvol storage — unchanged.** `zfs-server.nix` + `create-zfs-pool.sh` stay exactly as they are.

2. **Introduce mergerfs as the NAS bulk-pool namespace (`/storage` or `/tank-media`), with SnapRAID as the default parity layer (Option A).** This is the recipe that uniquely delivers "any drive, any size, add one at a time, media or general bulk," it is the most widely-operated and stable community NAS pattern, each disk stays independently recoverable, and — corrected from the prior doc — SnapRAID is now a **native `services.snapraid` module** with built-in sync/scrub timers, so the NixOS integration is small and declarative. New module shape (following Option B module pattern: common base + role addition):
   - `modules/server/mergerfs.nix` — `pkgs.mergerfs` + a `fileSystems."/storage"` entry (`fsType = "fuse.mergerfs"`, branch list, `category.create=mfs` / `moveonenospc=true` style policy).
   - `modules/server/snapraid.nix` — thin wrapper over `services.snapraid` (dataDisks/parity/content + sync & scrub timers).
   - A `create-mergerfs-pool.sh` companion to `create-zfs-pool.sh` for branch discovery, fstab/`fileSystems` wiring, and initial `snapraid sync`.
   - `cockpit.nix` Samba/NFS shares repoint from `/tank` to `/storage` — a one-line mountpoint change; the plugin is filesystem-agnostic.

3. **Point Nextcloud's primary data directory (and any DB-backed/churny service) at a dedicated ZFS mirror dataset, NOT at the SnapRAID pool.** The mergerfs/SnapRAID pool is ideal as Nextcloud *external storage* or a media library Nextcloud serves, but live small-file data belongs on ZFS for realtime redundancy. This satisfies "could be the pool for Nextcloud" honestly rather than putting churny data behind lagging parity.

4. **Offer per-disk ZFS branches as an opt-in, not the default.** If bitrot *repair* on the media pool matters more than raw capacity/simplicity, layer the "Perfect Media Server" stack (single-disk ZFS branches under mergerfs + SnapRAID). Default should stay plain mergerfs+SnapRAID to honor the "stable / simple / any drive" priority; ZFS-mirror branches are the wrong default because matched pairs contradict the mixed-drive goal.

5. **(Independent, optional) Add an Avahi `_smb._tcp` service record** if macOS/Bonjour auto-mount is wanted. Small, storage-agnostic, closes the one discovery gap noted in §3.

**Why this over "just expand ZFS":** ZFS alone cannot satisfy "pool from any kind of drive, add one at a time." Why not plain mergerfs+SnapRAID for *everything*: it fails the Nextcloud/churny and Proxmox workloads. The tiered split gives each workload the substrate it's actually good at, keeps every existing ZFS/Proxmox investment intact, and adds mergerfs only where its flexibility is the whole point.

---

## 6. Pitfalls / caveats (carried forward and updated)

1. **Migration is the real cost, not the module code** — existing NAS data must move to the new layout before the old is torn down; verify checksums before deleting sources.
2. **Physically separate NAS disks from Proxmox VM-storage disks** — do not mix mergerfs-branch disks and zvol disks in the same vdev/pool.
3. **SnapRAID protection is scheduled, not synchronous** — correct for media, wrong for Nextcloud live data (hence the ZFS tier for that).
4. **No Cockpit GUI for mergerfs/SnapRAID** — management is CLI/declarative; `cockpit-zfs` also still doesn't build at the pinned rev (unchanged by this).
5. **Parity disk sizing** — SnapRAID parity disk(s) must be ≥ the largest content disk; multiple parity disks (up to 6) tolerate multiple simultaneous failures.
6. **Discovery is unaffected by any of this** (see §3) — do not conflate the storage decision with network visibility.

---

## 7. Status

Research only; **no code changed.** If the operator approves this direction, the next step is a Phase 1 spec at `.github/docs/subagent_docs/nas_mergerfs_snapraid_spec.md` covering: the `modules/server/mergerfs.nix` + `modules/server/snapraid.nix` option surface, the `create-mergerfs-pool.sh` script, the `cockpit.nix` mountpoint repoint, the Nextcloud-on-ZFS wiring, and which server host trials the migration first.
