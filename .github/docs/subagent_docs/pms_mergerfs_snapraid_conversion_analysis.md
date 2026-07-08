# Analysis: Replacing the vexos-nix NAS/File-Sharing Storage Recipe with the "Perfect Media Server" (mergerfs + SnapRAID) Model

**Type:** Research analysis (Phase 1 — no implementation performed)
**Source reviewed:** https://perfectmediaserver.com/ (Tech Stack, mergerfs, SnapRAID, ZFS, "Using ZFS with mergerfs" pages)
**Scope:** This is specifically about the **NAS / bulk file-sharing storage recipe** — the pool Samba/NFS exports and media services (Jellyfin, `*arr`, Immich, etc.) write to. **ZFS for Proxmox VM/zvol storage is explicitly out of scope and stays as-is** — PMS's own "hybrid" pattern (ZFS pools used as mergerfs branches) means ZFS can still participate in the new NAS recipe too, just in a different role than today.
**Files reviewed:** `configuration-server.nix`, `configuration-headless-server.nix`, `modules/zfs-server.nix`, `modules/server/nas.nix`, `modules/server/cockpit.nix`, `modules/server/backup.nix`, `modules/server/scrutiny.nix`, `scripts/create-zfs-pool.sh`

---

## 1. How the vexos-nix NAS recipe currently works

There is no dedicated "NAS module" today — the NAS recipe is an assembly of pieces, and its storage layer happens to be **the same ZFS pool** that's also used for Proxmox VM storage:

| Layer | Component | File |
|---|---|---|
| Pool/redundancy | ZFS (mirror / raidzN / raid10) — one pool per host, created imperatively | [modules/zfs-server.nix](../../../modules/zfs-server.nix), [scripts/create-zfs-pool.sh](../../../scripts/create-zfs-pool.sh) |
| Pool layout | Root of the pool (`/tank`) is exported for NAS shares; an **optional child dataset** `tank/vm` is carved out specifically for Proxmox VM disks (`create-zfs-pool.sh` step 8) | [scripts/create-zfs-pool.sh](../../../scripts/create-zfs-pool.sh) |
| Web management | Cockpit + 45Drives plugins (navigator, file-sharing, identities) | [modules/server/cockpit.nix](../../../modules/server/cockpit.nix), [modules/server/nas.nix](../../../modules/server/nas.nix) |
| File sharing | Samba (registry mode) + NFS (v4-minimal or v3-compatible); exports whatever is mounted — filesystem-agnostic | [modules/server/cockpit.nix](../../../modules/server/cockpit.nix) |
| Disk health | Scrutiny (SMART web UI) + `smartd` — block-device level, filesystem-agnostic | [modules/server/scrutiny.nix](../../../modules/server/scrutiny.nix) |
| Data protection | Declarative restic backups of enabled `vexos.server.<service>` data dirs — path-based, filesystem-agnostic | [modules/server/backup.nix](../../../modules/server/backup.nix) |
| ZFS GUI | Deferred — `cockpit-zfs` fails to build at the pinned nixpkgs rev (Tailwind/PostCSS bug) | — |

**Key fact for this analysis:** today, one ZFS pool typically serves **both** roles on a server host — general NAS storage at the pool root, plus an optional `tank/vm` dataset for Proxmox. That coupling is exactly what makes "replace the NAS recipe" non-trivial: you can't touch the NAS side of the pool without thinking about what's sharing the same vdev as the VM side.

Redundancy/bitrot/snapshots/compression on the NAS side currently all come from ZFS itself (monthly `autoScrub`, weekly `trim`, `lz4`, `posixacl`). Expansion means growing a vdev or adding a new one; mixed disk sizes are supported but capped by the smallest disk per vdev.

---

## 2. How Perfect Media Server does the NAS side

PMS's flagship recipe for the storage/redundancy layer — the thing this analysis is about replacing — is **mergerfs + SnapRAID**, with ZFS-only and **ZFS+mergerfs hybrid** documented as alternatives.

### 2.1 mergerfs — the pooling layer

- A FUSE union filesystem that presents N independently-formatted disks/mounts (or, in the hybrid pattern, N independent ZFS datasets/pools) as one unified directory tree.
- Does no striping and no redundancy by itself — purely file placement (e.g., "most free space").
- Because each branch keeps its own native filesystem, pulling one disk out gives you its files back on any Linux box immediately — no array reassembly needed. This is PMS's headline reason to prefer it over striped/parity-integrated schemes for media libraries specifically.
- Disks of any size/model can be added one at a time with zero rebalancing of existing files.

### 2.2 SnapRAID — the parity layer

- Scheduled, out-of-band parity: dedicated parity disk(s) computed from content disks, refreshed by periodic `sync` (typically nightly/weekly via timer). A `scrub` mode checks already-synced data for silent bit-rot.
- Protection is only as fresh as the last sync — anything written since then is unprotected until the next sync runs. This is the central trade-off against ZFS's synchronous per-write parity.
- On disk failure: replace the disk, `snapraid fix` rebuilds **only that disk's used capacity** from parity + surviving disks — cheaper than a ZFS raidzN resilver, which reads/verifies the whole pool.
- Parity disk(s) must be ≥ the largest content disk; multiple parity disks (up to 6) tolerate multiple simultaneous failures (like raidz2/raidz3).
- Explicitly recommended only for **large, infrequently-changing files** — i.e. media libraries. Not for databases or anything else that rewrites constantly, because every sync gets expensive and the protection window degrades. (This is why VM storage staying on ZFS, as you've already decided, is the right call regardless of what happens to the NAS recipe.)

### 2.3 The ZFS+mergerfs hybrid PMS also documents

Use one or more ZFS pools/datasets (e.g. mirrors, or even single-disk pools) as mergerfs *branches* instead of plain ext4/XFS disks. You keep ZFS's realtime checksumming/scrub per branch and lose SnapRAID's sync-lag risk entirely, while still getting mergerfs's flexible one-disk-at-a-time pooling UX. Cost: you need actual redundant vdevs per branch (e.g. mirrors) rather than one large raidz, and you give up cross-disk striping efficiency. **This is the option most directly relevant to you**, since you already have ZFS expertise and tooling (`create-zfs-pool.sh`, `modules/zfs-server.nix`) in this repo, and it lets ZFS "be used with this if it can," as you asked.

---

## 3. What it would take to convert the NAS recipe (VM storage untouched)

### 3.1 Baseline decision: plain-disk mergerfs+SnapRAID vs. ZFS-backed mergerfs branches

Two viable shapes, both leaving `modules/zfs-server.nix` and Proxmox's `tank/vm` dataset exactly as they are today:

**Option A — Plain mergerfs+SnapRAID (PMS's default recipe).**
NAS disks are reformatted to ext4/XFS, pooled with mergerfs, protected with SnapRAID. Simplest mental model, matches PMS's main guide, but discards ZFS checksumming/bitrot detection for NAS data (SnapRAID's `scrub` is a partial substitute, run on your schedule rather than continuously).

**Option B — ZFS-backed mergerfs branches (PMS's hybrid).**
Each NAS "content disk" becomes its own small ZFS pool or dataset (e.g. single-disk or 2-disk mirror), and mergerfs pools those datasets' mountpoints into one tree. SnapRAID becomes optional/redundant here since ZFS already gives synchronous protection per branch — you'd likely skip SnapRAID entirely and just use mergerfs for the pooling/one-disk-at-a-time flexibility, keeping ZFS as the actual redundancy mechanism. This keeps you inside a filesystem you already operate (ZFS) while gaining mergerfs's "add one disk anytime, no rebalance" story that a single growing raidzN pool doesn't give you today.

Given you explicitly want ZFS to remain usable, **Option B is the closer fit to what you described** — it doesn't discard ZFS for NAS data, it just changes *how* ZFS pools are organized (many small pools/mirrors instead of one big pool) and adds mergerfs on top purely for unified namespace + flexible expansion.

### 3.2 Concrete implementation steps (either option)

1. **Separate the NAS dataset(s) from the VM dataset now, if not already physically separate.** Since Proxmox's `tank/vm` dataset currently can share a pool with NAS data, the safest precondition for this change is dedicating physically distinct disks to "VM storage" (stays on today's `zfs-server.nix` pool) vs. "NAS storage" (moves to the new recipe). Mixing mergerfs-branch disks and Proxmox zvol disks in the same physical vdev is not a supported pattern in either PMS's guide or your own tooling.
2. **Migrate existing NAS data.** Whatever currently lives in the ZFS pool's NAS-facing datasets needs to be copied to new destinations (new ZFS branch pools for Option B, or newly-formatted ext4/XFS disks for Option A) before the old NAS datasets/pool layout is torn down. This is a real data-migration project, not a config flip — plan for a window where data exists in two places, and verify checksums before deleting the source.
3. **New module(s), following the existing Option B (common base + role addition) pattern used elsewhere in this repo:**
   - `modules/server/mergerfs.nix`: package `mergerfs`; declarative `fileSystems."/storage"` entry (`fsType = "fuse.mergerfs"`, branch list, policy options string).
   - If Option B: no new redundancy module needed — reuse `modules/zfs-server.nix` machinery (hostId, kernel pin, autoScrub/trim) for the branch pools; just create more/smaller pools with `create-zfs-pool.sh` (already parameterized for topology/disk count) instead of one big one.
   - If Option A: `modules/server/snapraid.nix` — nixpkgs has **no native SnapRAID service module**, only the package, so `/etc/snapraid.conf` and the sync/scrub schedule need hand-authored `environment.etc` + `systemd.services`/`systemd.timers`, comparable in scope to what `zfs-server.nix` + `create-zfs-pool.sh` already do for ZFS.
   - Either way, a mergerfs-flavored companion to `create-zfs-pool.sh` is needed for initial setup (branch discovery, `fileSystems`/fstab wiring, and — Option A only — `snapraid.conf` generation + initial `snapraid sync`).
4. **`modules/server/cockpit.nix` (Samba/NFS) needs only a mountpoint change** — point shares at `/storage` (the mergerfs mount) instead of `/tank`. The plugin is filesystem-agnostic by design, so this is a one-line change once the new mount exists.
5. **`modules/server/backup.nix` (restic) and `modules/server/scrutiny.nix` (SMART) need no change** — both operate at a level (paths, block devices) that doesn't care about the pooling scheme.
6. **`modules/server/nas.nix`'s umbrella option** (`vexos.server.nas.enable`) doesn't need structural change — it currently just toggles Cockpit + plugins. It could optionally grow a `vexos.server.nas.backend = "zfs" | "mergerfs"` switch if you want the flake to describe which recipe a given host uses, but that's a nice-to-have, not a requirement.
7. **CI/preflight**: Phase 3/6's ZFS dry-build and `stateVersion`/`hardware-configuration.nix` checks are unaffected. If you go with Option A, add a parallel preflight check for `snapraid.conf` presence/syntax (`snapraid status` or similar, safe/read-only) alongside the existing ZFS checks.

---

## 4. Pitfalls

1. **Migration is the real cost, not the module code.** Whichever option, existing NAS data has to move to a new storage layout before the old one can be decommissioned — this is the bulk of the actual work and risk, independent of which recipe you land on.
2. **Physical disk separation from Proxmox VM storage becomes a hard requirement**, if it isn't already. Today's `create-zfs-pool.sh` allows one pool to serve both NAS root and a `tank/vm` child dataset; going forward, VM-storage disks and NAS-storage disks should be distinct vdevs/pools so that neither workload's I/O pattern (SnapRAID's bursty sync/scrub run, or mergerfs churn) affects the other, and so that a NAS-side layout change never touches the VM dataset.
3. **Option A loses ZFS's synchronous checksumming for NAS data.** SnapRAID's scrub is real but scheduled, not continuous — files can silently corrupt between scrubs. If bitrot protection matters for the NAS data (photos, irreplaceable media), Option B (ZFS-backed mergerfs branches) avoids this regression entirely, which is presumably why you're asking whether ZFS can still be "used with this."
4. **No upstream NixOS module for SnapRAID (Option A only).** Everything from config generation to scheduling to failure alerts (`onFailure =` hooks like `backup.nix` already does for restic) would be custom-written and repo-maintained, versus ZFS which mostly leans on first-class NixOS options (`boot.zfs.*`, `services.zfs.*`).
5. **Option B doesn't reduce operational surface area versus today** — you'd still be running `create-zfs-pool.sh`-style setup per branch pool, just more of them (smaller, more numerous) instead of one large pool. The benefit is purely the "add one disk/branch at a time without extending an existing vdev" flexibility mergerfs adds on top, not a simplification of ZFS operations themselves.
6. **No cockpit-zfs today regardless of path chosen** — the existing GUI gap (already deferred, per `nas.nix`/`cockpit.nix` comments) isn't fixed or worsened by this change; there's also no cockpit plugin for mergerfs/SnapRAID, so Option A trades one GUI gap for another (a differently-shaped one) rather than closing it.
7. **Rebuild-scope tradeoff (Option A) still applies**: SnapRAID rebuilds only the failed disk's used data (a real win for large media arrays vs. a raidzN whole-pool resilver), but during that rebuild a second failure outside the parity budget is just as unrecoverable as with any parity scheme.

---

## 5. Bottom line

- Proxmox VM/zvol storage stays on ZFS via `modules/zfs-server.nix` exactly as it is today — nothing here proposes touching that.
- For the NAS/file-sharing recipe itself, you have two realistic paths: **Option A** (plain mergerfs+SnapRAID, PMS's default — simplest, but drops ZFS's realtime checksumming for NAS data and requires writing a from-scratch SnapRAID NixOS integration) or **Option B** (ZFS-backed mergerfs branches, PMS's hybrid pattern — keeps ZFS doing the actual redundancy work you already trust and operate, with mergerfs purely as a pooling/expansion convenience layer on top).
- Samba/NFS (`cockpit.nix`), restic backups (`backup.nix`), and Scrutiny SMART monitoring (`scrutiny.nix`) all carry over unchanged in either option — the blast radius of this decision is genuinely scoped to the storage/pooling layer.
- The main real-world cost in both options is the data migration and (if not already true) physically separating NAS disks from Proxmox VM-storage disks — not the NixOS module work itself.
- This document is research only; no code changes were made. If you want to proceed, the next step would be a Phase 1 spec at `.github/docs/subagent_docs/nas_mergerfs_conversion_spec.md` picking Option A or B, scoping the new module's option surface, and identifying which server host would trial the migration first.
