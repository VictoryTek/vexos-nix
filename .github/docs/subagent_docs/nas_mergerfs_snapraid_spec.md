# Spec: Tiered NAS Storage (mergerfs + SnapRAID) with Enable-Time Storage Advisory

**Type:** Phase 1 specification (design only — no implementation performed)
**Builds on:** `nas_direction_analysis.md`, `pms_mergerfs_snapraid_conversion_analysis.md`
**Operator decisions locked in:**
- Missing-pool behavior = **prompt to launch** (advisory + `[y/N]`/menu, then chain into the create/attach script; never auto-wipe silently).
- Scope = **bundle the enable-time advisory with the mergerfs+SnapRAID rollout** so all storage tiers are covered at once.
- **Remote storage is a first-class option**: a service may consume a pool exported by *another* host (NFS/SMB), not only a locally-attached pool. The advisory and tooling must offer "attach a remote storage server" alongside "create a local pool."

---

## 1. Goal

Two coupled deliverables:

1. **A bulk-storage tier** built on mergerfs + SnapRAID, so a NAS pool can be assembled from *any* mixed-capacity drives, added one at a time — for media and general bulk storage. The existing ZFS pool (Proxmox VM storage) is left untouched.
2. **An enable-time storage advisory** in `just enable <service>`: when a service is best served by a particular storage tier, tell the operator which pool it wants, detect whether that pool exists, and offer to create it — so nobody wonders "which pool does this service use?"

Success criteria:
- `just create-mergerfs-pool` builds a working mergerfs pool from mismatched disks with SnapRAID parity, mounted at `/storage`.
- `just enable jellyfin` (etc.) prints the correct tier advice, detects pool presence, and offers to launch the matching create recipe.
- No existing ZFS/Proxmox behavior changes; all preflight/CI checks still pass.

---

## 2. Storage tiers → service mapping (authoritative)

Three tiers, distinguished by **data behavior**, not by service name. Each is a distinct mountpoint so workloads can't accidentally share disks.

| Tier | Mount | Substrate | Why | Create recipe |
|---|---|---|---|---|
| **VM** | `/tank/vm` (existing) | ZFS pool | Constant random block writes; zvols need synchronous integrity | `just create-zfs-pool` |
| **Live** | ZFS dataset (e.g. `/tank/data` or a dedicated mirror) | ZFS | Many small files, frequent rewrites, needs realtime redundancy + continuous checksums | `just create-zfs-pool` |
| **Bulk** | `/storage` | mergerfs + SnapRAID | Large, write-once/read-many, mixed drives, add one at a time | `just create-mergerfs-pool` (new) |
| **Remote** | operator-chosen (e.g. `/mnt/nas-media`) | NFS or CIFS client mount of a pool exported by another host | Storage lives on a separate NAS/storage server; this host is app-only | `just attach-remote-storage` (new) |

**Local vs. remote is orthogonal to the local backend.** A host may have a local ZFS/mergerfs pool, *or* attach one or more remote pools, *or* both. The `vexos.server.nas.backend` selector only describes the local pool type; remote mounts are declared independently under `vexos.server.storage.remote`. For the bulk and live tiers, a satisfied "storage need" = a local pool **or** a remote mount. The VM tier (`proxmox`) is local-only — VM block storage over NFS/CIFS is out of scope.

**Service classification** (drives the advisory in §5):

| Advisory class | Services | Message |
|---|---|---|
| `zfs-vm` | `proxmox` | "stores VM disks on a ZFS pool" |
| `zfs-live` | `nextcloud`, `immich`, `photoprism`, `paperless`, `minio`, `syncthing`, `forgejo` | "stores a database + many small files; recommended on a ZFS dataset for realtime redundancy" |
| `mergerfs-bulk` | `jellyfin`, `plex`, `navidrome`, `audiobookshelf`, `kavita`, `komga`, `arr` | "stores a large media library; recommended on a mergerfs+SnapRAID pool for mixed-drive expansion" |
| `none` (silent) | all others (adguard, grafana, vaultwarden, homepage, ntfy, cockpit, monitoring, DNS, SSO, etc.) | no prompt — small state on the OS disk |

Rationale notes:
- `immich`/`photoprism`/`nextcloud` hold originals that can be large, but they are DB-backed with live small-file churn → integrity/realtime-redundancy dominates → **zfs-live**. Bulk originals can still be placed on `/storage` as *external* storage by operator choice; the advisory recommends the safe default.
- Media streamers/`arr` are write-once large files → **mergerfs-bulk**.
- The mapping lives in **one place** (a shell case/assoc-array in the justfile) so it's easy to audit and extend.

---

## 3. New Nix modules (Option B pattern: common base + role addition)

### 3.1 `modules/server/mergerfs.nix`
- Declares `pkgs.mergerfs` in `environment.systemPackages`.
- Declares the pool as a `fileSystems."/storage"` entry: `fsType = "fuse.mergerfs"`, `device = "<branch1>:<branch2>:..."`, options string (e.g. `cache.files=partial,dropcacheonclose=true,category.create=mfs,moveonenospc=true,minfreespace=20G,fsname=storage`).
- Option surface under `vexos.server.storage.mergerfs`:
  - `enable` (bool)
  - `branches` (list of str) — content-disk mountpoints unioned into the pool
  - `mountPoint` (str, default `/storage`)
  - `extraOptions` (str, sensible default)
- No role-conditional `lib.mkIf` beyond the module's own `enable` (the standard toggleable-subsystem carve-out).

### 3.2 `modules/server/snapraid.nix`
- Thin wrapper over the **native `services.snapraid`** module (confirmed present in nixpkgs: `dataDisks`, `parityFiles`, `contentFiles`, `exclude`, `extraConfig`, `sync.interval`, `scrub.interval`, `scrub.plan`, `scrub.olderThan`, `touchBeforeSync`).
- Option surface under `vexos.server.storage.snapraid`:
  - `enable` (bool)
  - `dataDisks` (attrs name→path), `parityFiles` (list), `contentFiles` (list)
  - `syncInterval` / `scrubInterval` (str, default weekly/monthly) → map to the native timers
- `onFailure` notification hook wired to the repo's existing notify mechanism (mirror how `backup.nix` alerts).

### 3.3b `modules/server/storage-remote.nix` (remote pool client)
- Declares NFS/CIFS client mounts of pools exported by another host, so app services on this box can consume a remote NAS.
- Option surface under `vexos.server.storage.remote` — a `listOf submodule`:
  - `type` (enum `"nfs" | "cifs"`)
  - `server` (str — host/IP of the storage server)
  - `export` (str — NFS export path like `/tank/media`, or CIFS share name like `media`)
  - `mountPoint` (str — local mountpoint, e.g. `/mnt/nas-media`)
  - `credentialsFile` (nullOr path — CIFS only; `username=`/`password=` file, never inlined)
  - `options` (listOf str — sensible resilient defaults per type)
- `config` (active when the list is non-empty):
  - `fileSystems.<mountPoint>` per entry: `fsType = "nfs4"` or `"cifs"`, `device = "server:export"` / `"//server/share"`, options include `_netdev`, `nofail`, `x-systemd.automount`, `x-systemd.mount-timeout=30`; CIFS adds `credentials=<file>`, `uid`/`gid`, `file_mode`/`dir_mode`.
  - Adds `pkgs.nfs-utils` (nfs entries) / `pkgs.cifs-utils` (cifs entries) and `boot.supportedFilesystems` accordingly.
  - Assertion: CIFS entries must set `credentialsFile` (no anonymous/plaintext-inlined creds).

### 3.3 `modules/server/nas.nix` — add a backend selector
- Extend the existing umbrella with:
  - `vexos.server.nas.backend = lib.mkOption { type = enum [ "zfs" "mergerfs" ]; default = "zfs"; }`
- `backend = "mergerfs"` sets `vexos.server.storage.mergerfs.enable` (and, if the operator opts in, `snapraid.enable`) via `lib.mkDefault`, and repoints the Cockpit file-sharing default share root to `/storage`.
- Cockpit/Samba/NFS otherwise unchanged (filesystem-agnostic; only the mountpoint moves).

### 3.4 Imports + persistence wiring
- The new modules are imported via `modules/server/default.nix` (already imported by both server roles); they define options only and stay inert until enabled.
- **Persistence:** unlike ZFS (which self-persists via `zpool.cache`), mergerfs branch mounts, parity mounts, and remote mounts must be declared in Nix because NixOS generates `/etc/fstab`. The create/attach scripts write a single generated file `/etc/nixos/storage-pool.nix` (overwritten idempotently) holding `vexos.server.storage.*` values + `vexos.server.nas.backend`. This file is wired into the flake exactly parallel to `server-services.nix`:
  - `flake.nix`: add a `storagePoolModule = if pathExists /etc/nixos/storage-pool.nix then [ path ] else []` binding and append it to the `server` and `headless-server` `hostLocalModules`.
  - `template/etc-nixos-flake.nix`: mirror the same optional-file check in `mkServerVariant` and `mkHeadlessServerVariant`.
  - Absent file ⇒ empty list ⇒ server outputs still evaluate on hosts that never created a pool (same guarantee as `serverServicesModule`).

---

## 4. New script: `scripts/create-mergerfs-pool.sh`

Built as a sibling to `create-zfs-pool.sh`, reusing its structure/idioms (colored `die/warn/ok/hdr`, `[n/N]` step headers, OS-disk exclusion via `lsblk` PKNAME/MOUNTPOINT/FSTYPE, `/dev/disk/by-id/` enumeration, typed-name destructive confirmation).

Steps:
1. Preconditions (root, `mergerfs` present, `snapraid` present).
2. Enumerate eligible disks (same exclusion logic as ZFS script; additionally **exclude disks already in a ZFS pool** so the VM/live tier disks can't be grabbed).
3. Select **content** disks and **parity** disk(s) separately; enforce parity ≥ largest content disk.
4. Confirm (typed pool/mount name).
5. Format content + parity disks (ext4 or XFS), create per-disk mountpoints (e.g. `/mnt/disk1..N`, `/mnt/parity1..M`), write `/etc/fstab` (or emit the `fileSystems`/`vexos.server.storage.*` snippet for the operator to paste into `server-services.nix`).
6. Generate `/etc/snapraid.conf` (or the `vexos.server.storage.snapraid` snippet), run initial `snapraid sync`.
7. Print the exact lines to add to `/etc/nixos/server-services.nix` (`vexos.server.nas.backend = "mergerfs";` + branch/parity config) and remind to `just rebuild`.

Idempotent up to the destructive step, same as the ZFS script.

---

## 5. justfile changes

### 5.1 New recipe `create-mergerfs-pool`
- Copy the `create-zfs-pool` recipe (line ~1221): `_require-server-role`, same script-location walk, `sudo bash scripts/create-mergerfs-pool.sh`.
- Add a one-line entry to the server help block (near line 20) and to `available-services` if appropriate.

### 5.2 Enable-time storage advisory (in the `enable` recipe, ~line 1655)
Inserted **after** the service name is validated and **before** (or right after) the flag is written — advisory runs once per enable.

Logic (behavior = **prompt to launch**):
```
tier = lookup(SERVICE)         # zfs-vm | zfs-live | mergerfs-bulk | none
if tier == none: skip silently

print advisory line for tier   # e.g. "jellyfin stores a large media library..."

# A storage need is satisfied by a LOCAL pool OR a REMOTE mount (except zfs-vm).
local_present =
    tier in {zfs-vm, zfs-live}  -> `zpool list -H -o name` non-empty
    tier == mergerfs-bulk       -> `mountpoint -q /storage`
remote_present =
    tier == zfs-vm  -> false            # VM block storage is local-only
    else            -> `findmnt -rn -t nfs,nfs4,cifs` non-empty

if local_present or remote_present:
    print "Detected: <pool/mount> — OK." ; continue
else:
    print "No local pool or remote storage detected."
    # zfs-vm: only offer local ZFS. bulk/live: offer all three.
    menu:
      1) Local mergerfs+SnapRAID pool   -> just create-mergerfs-pool   (bulk/live only)
      2) Local ZFS pool                 -> just create-zfs-pool
      3) Attach a remote storage server -> just attach-remote-storage   (bulk/live only)
      4) Skip — configure later
    launch the chosen recipe, or print the reminder on Skip.
# the vexos.server.<service>.enable flag is written regardless;
# the advisory never blocks enabling, it only informs + offers.
```

Details:
- The tier mapping is a single shell function/case at the top of the recipe (auditable, one edit point).
- Detection commands are **read-only and safe** (`zpool list`, `mountpoint -q`, `findmnt`); no FORBIDDEN COMMANDS.
- Chaining calls the existing/new `just` recipes, which keep their own destructive confirmations — the disk-wipe is always behind a typed-name gate; `attach-remote-storage` is non-destructive (client mount only).
- `arr` special-cases already exist in the recipe; the advisory runs before that block (arr → `mergerfs-bulk`).
- Non-interactive/CI invocation guard: if stdin is not a TTY, skip the menu and fall through to the "Skipped" message (do not hang CI).

### 5.3 New recipe `attach-remote-storage`
- `_require-server-role`; runs `scripts/attach-remote-storage.sh`.
- Script (non-destructive): prompt for protocol (NFS/CIFS), server, export/share, local mountpoint, and — for CIFS — a credentials file path; test-mount to validate; then emit the `vexos.server.storage.remote` entry into `/etc/nixos/storage-pool.nix` (same generated file the local-pool script writes) and remind to `just rebuild`.

---

## 6. Risks & mitigations

| Risk | Mitigation |
|---|---|
| Advisory misclassifies a service | Mapping is centralized and conservative (default to the safer ZFS-live for DB-backed services); easy to adjust in one place |
| Chained create script wipes wrong disks | create scripts exclude OS disks *and* ZFS-member disks; typed-name confirmation retained |
| mergerfs data has no bitrot repair by default | SnapRAID scrub scheduled; document per-disk-ZFS-branch opt-in as a future enhancement (not default — contradicts mixed-drive goal) |
| SnapRAID protection lag on churny data | Advisory steers churny/DB services to the ZFS-live tier, never to `/storage` |
| Enable recipe becomes interactive/hangs in automation | TTY guard skips prompts when non-interactive |
| Migration of existing NAS data | Out of scope for this spec — see `nas_direction_analysis.md` §6; handle as a separate operator-run step |

---

## 7. Out of scope / future

- Data migration from the current single-ZFS-pool NAS layout to the tiered layout (separate operational task).
- Per-disk ZFS branches under mergerfs ("Perfect Media Server" full stack) — opt-in enhancement, not the default.
- Avahi `_smb._tcp` service record for macOS/Bonjour auto-mount — independent, storage-agnostic (noted in `nas_direction_analysis.md` §3).
- Cockpit GUI for mergerfs/SnapRAID — none exists upstream.

---

## 8. Build/validation plan (for Phase 3)

- `nix flake show --impure` (structure).
- `sudo nixos-rebuild dry-build --flake .#vexos-server-amd` and `.#vexos-headless-server-amd` (server modules touched).
- `git ls-files hardware-configuration.nix` empty; `system.stateVersion` unchanged.
- `just --evaluate`/shellcheck the new recipe + script (no `nix flake check`).
- Confirm `services.snapraid` + `mergerfs` attribute paths resolve at the pinned rev.

---

## 9. Status

Design only — **no code changed.** On approval, Phase 2 implements: `modules/server/mergerfs.nix`, `modules/server/snapraid.nix`, the `vexos.server.nas.backend` option, `scripts/create-mergerfs-pool.sh`, and the two justfile changes (new recipe + enable-time advisory).
