# SMB / NFS Discovery in GNOME Files (Nautilus) — Research & Specification

## Feature Name
`smb_nfs_discovery`

## Date
2026-04-28

---

## 1. Current State Analysis

### 1.1 Symptom (as reported)

In GNOME Files (Nautilus) → **Network** sidebar entry:

- ✅ FTP / SFTP locations discover and appear (likely from saved bookmarks / connected servers, **not** from auto-discovery — see §3.4).
- ❌ SMB (Windows / Samba) hosts and shares do **not** appear.
- ❌ NFS exports do **not** appear.

### 1.2 What is already configured (`origin/main`, commit `3082227`)

`modules/network.nix` (universal base, all roles):

- `services.avahi.enable = true`
- `services.avahi.nssmdns4 = true`
- `services.avahi.openFirewall = true`  → opens UDP 5353
- `cifs-utils` installed (kernel CIFS mount helper)

`modules/network-desktop.nix` (display-role addition; imported by desktop, htpc, server, stateless — **not** headless):

- `services.samba.enable = true`
  - `smbd.enable = lib.mkDefault false`
  - `nmbd.enable = lib.mkDefault false`
  - `winbindd.enable = lib.mkDefault false`
  - `settings.global.workgroup = "WORKGROUP"`
  - `settings.global."client min protocol" = "SMB2"`
  - `settings.global."client max protocol" = "SMB3"`
- `services.avahi.publish = { enable = true; userServices = true; }`
- `services.samba-wsdd.enable = true`
- `services.samba-wsdd.openFirewall = true`
- `systemd.tmpfiles.settings."10-samba-etc"` symlinks `/etc/samba` → `/etc/static/samba`
- `boot.supportedFilesystems = [ "nfs" ]`

GNOME stack (`modules/gnome.nix`) auto-enables `services.gvfs.enable = true` via the GNOME desktop manager module. Live diagnostics from the previous spec (v3) confirmed `gvfsd-smb`, `gvfsd-smb-browse`, `gvfsd-network`, `gvfsd-dnssd`, and `gvfsd-wsdd` binaries are present and `samba` is in the gvfs closure (libsmbclient is linked).

### 1.3 The three previous attempts and exactly why they failed

| # | Commit | Change | Why it did not fix the user's symptom |
|---|---|---|---|
| v1 | `bec7bec` | Added `services.avahi.publish`, `services.samba-wsdd` (responder), `boot.supportedFilesystems = [ "nfs" ]`, `samba` package | Enabled WSDD as **responder only** (advertises this host) but **never enabled `discovery` mode**, so this host never queries the LAN for Windows/Samba hosts. No `smb.conf` was generated, so libsmbclient could not initialise. |
| v2 | `da6e40c` | Added `services.samba.enable = true` (client-only) to generate `/etc/samba/smb.conf` | Fixed the libsmbclient init path, but `gvfsd-smb-browse` workgroup browsing on a modern LAN returns empty (browser election requires nmbd somewhere). Still **no WSDD discovery mode** → `gvfsd-wsdd` had no host list to read. |
| v3 | `3082227` | Added `systemd.tmpfiles` rule to guarantee `/etc/samba` symlink exists | Fixed a real activation race (smb.conf is now reachable on every boot), but the underlying discovery problem is **independent** of smb.conf. **WSDD is still responder-only**, so `gvfsd-wsdd` still has no peers to enumerate. Workgroup browsing via `gvfsd-smb-browse` still returns empty. |

**Net result**: the chain `Nautilus → gvfsd-network → {gvfsd-smb-browse, gvfsd-dnssd, gvfsd-wsdd}` has all components installed and reachable, but **none of those three discovery sources are returning hosts**:

1. `gvfsd-smb-browse` (libsmbclient workgroup browsing) — relies on a NetBIOS browse-master being elected on the LAN. Modern Windows 10/11 disables NetBIOS browsing by default; nobody on the LAN holds the browse-master role; result is empty.
2. `gvfsd-dnssd` (Avahi mDNS) — only finds hosts that **advertise** `_smb._tcp` / `_nfs._tcp` via mDNS. Windows hosts do not. Most Linux SMB/NFS servers do not unless explicitly configured. Result is typically empty on a Windows-heavy LAN.
3. `gvfsd-wsdd` (Web Services Discovery client) — connects to a local wsdd unix socket (`/run/wsdd/wsdd.sock`) populated by **wsdd in discovery mode**. Our wsdd is in **responder mode only** (default). The socket is never created → gvfsd-wsdd has no host list → result empty.

---

## 2. Root Cause

**`services.samba-wsdd.discovery` defaults to `false` in NixOS, and we never set it to `true`.**

Verified directly in nixpkgs (`nixos/modules/services/network-filesystems/samba-wsdd.nix`):

```nix
discovery = lib.mkOption {
  type = lib.types.bool;
  default = false;
  description = "Enable discovery operation mode.";
};
listen = lib.mkOption {
  type = lib.types.str;
  default = "/run/wsdd/wsdd.sock";
  description = "Listen on path or localhost port in discovery mode.";
};
```

And in the unit's `ExecStart`:

```
${lib.optionalString cfg.discovery "--discovery --listen '${cfg.listen}'"}
```

Without `discovery = true`, `wsdd` runs purely as a **responder** — it answers WSD probes from Windows machines so that *this* host shows up in *their* network neighbourhood, but it **never sends Probe messages itself** and **never opens the discovery socket** that GVfs's `gvfsd-wsdd` backend reads from. The GVfs WSDD backend has nothing to enumerate, so the Network view stays empty.

This is corroborated by the upstream nixos test (`nixos/tests/samba-wsdd.nix`) which sets `discovery = true` on the *client* node and leaves it `false` on the *server* node — the explicit pattern: clients that want to **see** other hosts must enable discovery mode.

### Secondary contributors (not the primary failure but worth fixing)

- `services.avahi.publish.addresses` is not set. Without it, this host's IPv4/IPv6 are not announced to other Linux/macOS hosts via mDNS, weakening reverse discovery.
- `services.avahi.publish.workstation` is not set. Useful so other GVfs/Bonjour clients see this host as `_workstation._tcp`.
- The samba `settings.global` is missing `"server min protocol" = "SMB2"`. Not relevant for browsing (server is disabled), but worth setting for correctness if the server is ever flipped on.

---

## 3. Honest Caveats the User Must Know

These are facts about how Linux distros actually behave — **not** vexos-specific bugs. The user explicitly asked us not to repeat the previous mistakes, and one of those mistakes is conflating "Ubuntu/Fedora ship something out of the box" with "Ubuntu/Fedora auto-discover everything".

### 3.1 NFS auto-discovery is NOT a standard feature on Ubuntu or Fedora

- GVfs **does not ship an `nfs-browse` backend.** Verified: only `smb-browse`, `dns-sd`, and `wsdd` exist. There is no scan that enumerates NFS exports on the LAN.
- Ubuntu and Fedora do **not** auto-discover NFS shares in Nautilus by default. NFS is conventionally mounted via `/etc/fstab`, autofs, or typed manually as `nfs://host/export` in the Nautilus location bar (Ctrl+L).
- An NFS export *can* be discovered if the NFS server explicitly advertises `_nfs._tcp` via mDNS/Avahi. Synology and some macOS configurations do this; **stock Ubuntu/Fedora/Windows NFS servers do not.** This is a server-side configuration, not a client-side fix.
- **What this spec does and does not do for NFS**: this spec keeps `boot.supportedFilesystems = [ "nfs" ]` so that *manually-typed* `nfs://server/export` URLs work in Nautilus and that mounted NFS shares appear in the sidebar. It does **not** make NFS exports auto-appear in the Network view, because no Linux distro does that out of the box.

### 3.2 SMB workgroup browsing on modern LANs is unreliable regardless of distro

- Workgroup browsing (the legacy Windows "Network Neighbourhood" mechanism) needs a NetBIOS browse-master to be elected. With Windows 10/11 disabling SMB1/NetBIOS browsing by default, this election often fails on home LANs.
- The reliable modern mechanism is **WS-Discovery**. That is exactly what this spec fixes.
- After this fix, hosts that show up will be those advertising via WSD (Windows 10/11 with file sharing, modern Samba with WSDD) or mDNS (`_smb._tcp` — macOS and some NAS).
- A pure Linux LAN whose servers don't run wsdd or advertise `_smb._tcp` may still appear empty. That is correct and unavoidable without server-side configuration.

### 3.3 GNOME 46+ Nautilus Network view is intentionally minimal

GNOME upstream removed the old "Other Locations" pane in 46. The "Network" sidebar entry still functions and routes to `network:///`, which is handled by `gvfsd-network` aggregating the three sources above. There is no per-distro magic — Ubuntu and Fedora go through the same code path. They get hits because they happen to ship `wsdd` configured in discovery mode by default; we do not.

### 3.4 SFTP "showing up" in the user's sidebar

GNOME Files does **not** auto-discover SFTP servers on the LAN. The reason FTP/SFTP entries appear in the user's sidebar is one of:

- A previously-mounted SFTP location is being kept in **Connected Servers** / sidebar history;
- An entry was bookmarked manually;
- A `_sftp-ssh._tcp` or `_ftp._tcp` mDNS service is being advertised by some host on the LAN (Avahi → gvfsd-dnssd → sidebar entry).

This means `gvfsd-dnssd` is already working. SMB hosts are absent because nothing on the LAN is publishing `_smb._tcp` over mDNS and our local WSDD is not in discovery mode.

---

## 4. Proposed Solution

A single, surgical change to `modules/network-desktop.nix`. **No new files.** **No new flake inputs.** **No `lib.mkIf` guards.** Strict adherence to the project's Option B module pattern.

### 4.1 Changes

| Change | Reason |
|---|---|
| `services.samba-wsdd.discovery = true;` | **Primary fix.** Switches wsdd from responder-only to responder-and-discovery. Creates `/run/wsdd/wsdd.sock` which `gvfsd-wsdd` reads to populate the Network view. |
| `services.avahi.publish.addresses = true;` | Announce this host's addresses via mDNS so other GVfs clients can resolve and reverse-discover this machine. |
| `services.avahi.publish.workstation = true;` | Advertise `_workstation._tcp` so other Linux/macOS hosts list this machine as a browsable workstation. |
| Comment block update | Document the discovery-mode requirement so this trap isn't fallen into a fourth time. |

That is the entire fix. Everything else from the v3 commit (`services.samba.enable` for smb.conf, the `/etc/samba` tmpfiles symlink, `samba-wsdd.openFirewall`, `boot.supportedFilesystems = [ "nfs" ]`, the avahi `publish.enable` and `userServices`) stays exactly as it is — it was correct, just incomplete.

### 4.2 Concrete file edit

**File:** `modules/network-desktop.nix`

In the `services.samba-wsdd` block, add `discovery = true;`:

```nix
services.samba-wsdd = {
  enable       = true;
  openFirewall = true;
  discovery    = true;     # ← required so gvfsd-wsdd can read /run/wsdd/wsdd.sock
};
```

In the `services.avahi.publish` block, add `addresses` and `workstation`:

```nix
services.avahi.publish = {
  enable       = true;
  addresses    = true;
  workstation  = true;
  userServices = true;
};
```

Update the WSDD comment to record *why* `discovery = true` matters (so the next person doesn't remove it). Suggested wording:

```
# ── WS-Discovery (WSDD) — RESPONDER + DISCOVERY ─────────────────────────
# `enable` alone runs wsdd as a responder only — it announces this host to
# Windows but never enumerates other WSD hosts on the LAN. GVfs's gvfsd-wsdd
# backend reads the wsdd discovery socket (default /run/wsdd/wsdd.sock),
# which only exists when `discovery = true`. Without that, the Nautilus
# "Network" view stays empty even though smb.conf, libsmbclient, and Avahi
# are all correctly configured. This was the root cause of three prior
# failed attempts (commits bec7bec, da6e40c, 3082227).
```

### 4.3 Files modified

- `modules/network-desktop.nix` — only file touched in Phase 2.

### 4.4 Files **not** modified (deliberately)

- `modules/network.nix` — unchanged. Avahi base config is correct.
- `modules/gnome.nix`, `modules/gnome-desktop.nix` — GVfs is auto-enabled by GNOME; nothing to do.
- `configuration-*.nix` — no import changes needed; all four GNOME-based roles already import `network-desktop.nix`.
- `flake.nix` — no new inputs.
- Headless-server roles — deliberately untouched. No discovery there.

---

## 5. Architecture Compliance (Option B)

- ✅ Change is in `modules/network-desktop.nix` — a role-specific addition file, not a shared module.
- ✅ No `lib.mkIf` guards added.
- ✅ All settings apply unconditionally to every role that imports the file.
- ✅ Headless-server (`configuration-headless-server.nix`) does not import `network-desktop.nix` — discovery stays off there as intended.
- ✅ `system.stateVersion` untouched.
- ✅ `hardware-configuration.nix` untouched (host-managed).

---

## 6. Dependencies

No new flake inputs. No new packages. The fix toggles existing NixOS-module options:

| Option | NixOS module | Verified via |
|---|---|---|
| `services.samba-wsdd.discovery` | `nixos/modules/services/network-filesystems/samba-wsdd.nix` | nixpkgs source @ commit `0726a0ec`; `search.nixos.org` |
| `services.avahi.publish.addresses` | `nixos/modules/services/networking/avahi-daemon.nix` | NixOS options |
| `services.avahi.publish.workstation` | `nixos/modules/services/networking/avahi-daemon.nix` | NixOS options |

Firewall ports already opened by existing config (UDP 5353 mDNS, UDP 3702 + TCP 5357 WSDD). **No new ports.** The wsdd discovery socket is a **local Unix socket** at `/run/wsdd/wsdd.sock` — it is not network-exposed and requires no firewall rules.

---

## 7. Post-rebuild Testing Steps

After `sudo nixos-rebuild switch --flake .#vexos-desktop-amd` (or the user's variant), the user can run:

1. **Confirm wsdd is in discovery mode** (the unit cmdline must contain `--discovery`):
   ```bash
   systemctl status samba-wsdd
   systemctl show samba-wsdd -p ExecStart | tr ' ' '\n' | grep -E 'discovery|listen'
   ```
   Expect: `--discovery` and `--listen /run/wsdd/wsdd.sock`.

2. **Confirm the discovery socket exists**:
   ```bash
   ls -l /run/wsdd/wsdd.sock
   ```

3. **Confirm wsdd has discovered peers** (give it ~30 s after a `wsdd` restart for Probe/ProbeMatch round-trip):
   ```bash
   sudo journalctl -u samba-wsdd -n 50 --no-pager | grep -iE 'probe|hello|discover'
   ```

4. **Browse mDNS** for what Avahi already sees:
   ```bash
   avahi-browse -a -t -r | grep -E 'smb|workstation|nfs|sftp'
   ```

5. **Restart the user's gvfs daemon** so it re-mounts the wsdd backend with the new socket:
   ```bash
   systemctl --user restart gvfs-daemon
   # or just log out and back in
   ```

6. **Open Nautilus → Other Locations / Network sidebar entry.** Hosts advertising via WSD or `_smb._tcp` should now appear.

7. **Manual SMB / NFS access still works** for hosts that don't advertise:
   - `Ctrl+L` → `smb://<hostname-or-ip>/`
   - `Ctrl+L` → `nfs://<hostname>/<export>`

---

## 8. Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| `wsdd` in discovery mode chats more on the LAN, increasing UDP 3702 multicast | Certain (by design) | Negligible — a few packets per minute | None needed. This is the documented purpose of WSDD discovery. |
| Discovery exposes the wsdd socket at `/run/wsdd/wsdd.sock` to other local users | Low | Low — peer list is public LAN information anyway | The NixOS unit creates `/run/wsdd` with mode `0750` and `DynamicUser=true`. Socket is not world-writable. |
| Some firewalls / VPNs block multicast | Possible on locked-down networks | Discovery returns nothing | Out of scope. Documented in §3.2 caveats. |
| The user expects NFS to auto-appear and it still does not | Certain | UX surprise | §3.1 of this spec is explicit. If the user wants this anyway, they must configure their NFS server (out of scope) to advertise `_nfs._tcp` via Avahi. |
| Future regression: someone removes `discovery = true` thinking it's redundant | Medium | High (breaks discovery again) | Explanatory comment in `modules/network-desktop.nix` (§4.2) records the failure history. |
| Build failure | Very low | Medium | Option exists in nixpkgs; pure boolean; no eval pitfalls. Validate with `nix flake check` and `nixos-rebuild dry-build`. |

---

## 9. Research Sources

1. **`nixos/modules/services/network-filesystems/samba-wsdd.nix`** (nixpkgs @ `0726a0ec`) — defines `discovery` option (default `false`) and confirms `--discovery --listen /run/wsdd/wsdd.sock` is only added to ExecStart when true.
2. **`nixos/tests/samba-wsdd.nix`** — upstream test; the *client* node sets `discovery = true`, confirming this is the intended pattern for hosts that want to enumerate peers.
3. **`pkgs/by-name/ws/wsdd/package.nix`** — confirms the wsdd binary used (christgau/wsdd) and that discovery vs. responder is a runtime flag.
4. **upstream wsdd README (christgau/wsdd)** — documents that discovery mode is the only mode that actively probes the LAN and exposes a socket consumable by Linux file managers (gvfs).
5. **GVfs source — `gvfsbackendwsdd.c`** (gvfs 1.58) — confirms the wsdd backend connects to a local wsdd unix socket to retrieve discovered hosts; without the socket the backend is a no-op.
6. **GVfs `gvfsbackendsmbbrowse.c`** — confirms libsmbclient workgroup enumeration depends on a browse-master being elected on the LAN; not reliable on modern Windows-only LANs.
7. **`search.nixos.org/options?query=services.samba-wsdd`** — lists all 10 options (`enable`, `discovery`, `domain`, `extraOptions`, `hoplimit`, `hostname`, `interface`, `listen`, `openFirewall`, `workgroup`); confirms canonical names.
8. **`nixos/modules/services/networking/avahi-daemon.nix`** — confirms `publish.addresses` and `publish.workstation` options exist and default to `false`.
9. **Arch Wiki — GNOME/Files § "Network places do not appear"** — recommends `wsdd` (in discovery mode) as the modern replacement for NetBIOS browsing.
10. **Fedora `samba` package post-install scripting and Ubuntu `samba-common` defaults** — both ship `wsdd` (or `wsdd2`) configured in discovery mode by default; this is the default-config delta that explains why it "just works" on those distros.
11. **GNOME `gvfs` package definition (`pkgs/by-name/gv/gvfs/package.nix`)** — confirms our gvfs is built with `samba`, `avahi`, and `libnfs` in `buildInputs`, so all three backends are compiled in. Not a packaging issue.
12. **GNOME upstream Nautilus issue tracker (Network view work items)** — confirms there is no NFS-discovery view planned and that `gvfsd-network` aggregation has not changed in design.

---

## 10. Summary for Orchestrator

- **Root cause**: `services.samba-wsdd.discovery` defaults to `false`. Without it, the WSDD socket that GVfs reads is never created, so the Nautilus Network view never lists discovered Windows / Samba hosts. All three previous attempts addressed adjacent issues (Avahi publishing, smb.conf existence, `/etc/samba` activation race) without flipping this one boolean.
- **Fix**: in `modules/network-desktop.nix`, set `services.samba-wsdd.discovery = true;` and add `addresses = true; workstation = true;` to `services.avahi.publish`. No new files, no new inputs, no guards.
- **Honest NFS caveat**: NFS exports are *not* auto-discovered in Nautilus on Ubuntu, Fedora, or anywhere else by default. GVfs has no NFS browse backend. NFS shares must be mounted via fstab/autofs or typed manually as `nfs://host/export`. The user's expectation here is incorrect and should be communicated clearly. This spec keeps NFS *kernel/client* support so manual `nfs://` URLs work.
- **Files to be modified in Phase 2**: `modules/network-desktop.nix` (only).
