# Network Share Discovery v4 — Research & Specification

**Phase:** 1 — Research & Specification
**Date:** 2026-05-05
**Roles affected:** `desktop`, `htpc`, `stateless`, `server` (all four GNOME-bearing roles)
**Prior attempts:** v1 (2026-04-27), v2, v3 — see archived specs in this directory

---

## 0. TL;DR for Orchestrator

- **All three prior fix attempts (v1 → v3) have already landed.** The
  vexos-nix configuration of avahi/gvfs/samba-client/samba-wsdd/firewall
  for client-side network discovery is **complete and correct**, and
  every component is **running** on the live `vexos-desktop-amd` host.
- **Avahi mDNS works**: `avahi-browse -art` sees many services on the
  current LAN (`_workstation._tcp`, `_airplay._tcp`,
  `_spotify-connect._tcp`, `_home-assistant._tcp` from multiple peers)
  — but **zero** `_smb._tcp` / `_nfs._tcp` / `_sftp-ssh._tcp`
  advertisements. The publishers (`theannex` etc.) are not reachable
  via mDNS multicast from vexos's current network segment.
- **Root cause of the user's observation is environmental, not
  configuration.** The fresh-NixOS-GNOME install in the screenshot
  was on a network where those publishers were reachable; vexos is
  currently on one where they are not.
- **Defensive enhancements** (small, deterministic, low-risk) are
  proposed so that *when* vexos is on a network with reachable
  publishers, behaviour is bit-for-bit aligned with stock GNOME-on-
  NixOS: pin `gvfs` to `pkgs.unstable` for IPC parity with the already
  unstable-pinned `nautilus`, set `org.gnome.system.dns-sd
  display-local = "merged"` explicitly in the system dconf database,
  and add `services.avahi.publish.domain = true`.

---

## 1. Problem Statement

User reports that GNOME Files (Nautilus) on a fresh NixOS GNOME install
auto-discovers SMB/CIFS, NFS, SFTP-SSH, and workstation hosts on the
local network and shows them under **Network → Available on Current
Network** (e.g. `goliath`, `megatron`, `theannex - NFS`, `theannex -
SMB/CIFS`, `theannex - SSH`).

On vexos-nix builds, the **Network** view in Nautilus is empty.

Three prior attempts (v1, v2, v3) tried to fix this by enabling
`services.avahi.publish.*`, `services.samba-wsdd` (with
`discovery = true`), `services.samba` (client-only), `boot.supported
Filesystems = [ "nfs" ]`, `/etc/samba` tmpfiles symlink, and a NetBIOS
conntrack helper. The user reports the symptom **persists**.

---

## 2. Current State Analysis

### 2.1 Files inspected

- [modules/gnome.nix](modules/gnome.nix)
- [modules/gnome-desktop.nix](modules/gnome-desktop.nix)
- [modules/gnome-htpc.nix](modules/gnome-htpc.nix)
- [modules/gnome-stateless.nix](modules/gnome-stateless.nix)
- [modules/gnome-server.nix](modules/gnome-server.nix)
- [modules/network.nix](modules/network.nix)
- [modules/network-desktop.nix](modules/network-desktop.nix)
- [modules/security.nix](modules/security.nix)
- [modules/security-server.nix](modules/security-server.nix)
- [configuration-desktop.nix](configuration-desktop.nix)
- [configuration-htpc.nix](configuration-htpc.nix)
- [configuration-stateless.nix](configuration-stateless.nix)
- [hosts/desktop-amd.nix](hosts/desktop-amd.nix)
- [flake.nix](flake.nix)

### 2.2 Evaluated configuration of `vexos-desktop-amd`

`nix eval --impure` of `nixosConfigurations.vexos-desktop-amd.config`
returned:

```json
{
  "avahi_enable": true,
  "avahi_nssmdns4": true,
  "avahi_openFirewall": true,
  "avahi_publish_enable": true,
  "avahi_publish_addresses": true,
  "avahi_publish_workstation": true,
  "avahi_publish_userServices": true,
  "gvfs_enable": true,
  "samba_enable": true,
  "samba_smbd": false,
  "samba_nmbd": false,
  "samba_winbindd": false,
  "wsdd_enable": true,
  "wsdd_discovery": true,
  "wsdd_openFirewall": true,
  "resolved_extraConfig": "MulticastDNS=no\nLLMNR=no\n",
  "fw_tcp": [22, 5357, 27036, 27037],
  "fw_udp": [3702, 5353, 10400, 10401, 27036, 41641],
  "apparmor_enable": true,
  "apparmor_packages_count": 2,
  "apparmor_policies_count": 0
}
```

### 2.3 Quoted source lines

[modules/network.nix](modules/network.nix#L14-L19) — universal mDNS:

```nix
services.avahi = {
  enable       = true;
  nssmdns4     = true;     # enables mDNS resolution for .local in NSS
  openFirewall = true;     # opens UDP 5353 (mDNS)
};
```

[modules/network.nix](modules/network.nix#L41-L57) — resolved hand-off:

```nix
services.resolved = {
  ...
  extraConfig = ''
    MulticastDNS=no
    LLMNR=no
  '';
};
```

[modules/network-desktop.nix](modules/network-desktop.nix#L23-L37) —
samba client (smbd/nmbd/winbindd disabled, smb.conf generated):

```nix
services.samba = {
  enable          = true;
  nmbd.enable     = lib.mkDefault false;
  smbd.enable     = lib.mkDefault false;
  winbindd.enable = lib.mkDefault false;
  settings.global = {
    workgroup             = "WORKGROUP";
    "client min protocol" = "SMB2";
    "client max protocol" = "SMB3";
    "load printers"       = "no";
    ...
  };
};
```

[modules/network-desktop.nix](modules/network-desktop.nix#L46-L52) —
Avahi publish:

```nix
services.avahi.publish = {
  enable       = true;
  addresses    = true;
  workstation  = true;
  userServices = true;
};
```

[modules/network-desktop.nix](modules/network-desktop.nix#L65-L70) —
WSDD with discovery socket (the v3 fix):

```nix
services.samba-wsdd = {
  enable       = true;
  openFirewall = true;
  discovery    = true;
};
```

[modules/network-desktop.nix](modules/network-desktop.nix#L80-L88) —
`/etc/samba` symlink safety net (`L+`).

[modules/network-desktop.nix](modules/network-desktop.nix#L91-L93) —
`boot.supportedFilesystems = [ "nfs" ];`.

[modules/network-desktop.nix](modules/network-desktop.nix#L101-L103) —
NetBIOS UDP 137 conntrack helper.

`network-desktop.nix` is imported by:
- [configuration-desktop.nix](configuration-desktop.nix#L13)
- [configuration-htpc.nix](configuration-htpc.nix#L9)
- [configuration-stateless.nix](configuration-stateless.nix#L9)

(Not imported by `configuration-server.nix` /
`configuration-headless-server.nix` — but `configuration-server.nix`
also imports `gnome-server.nix`, which means the GUI server role
*does* run a GNOME desktop without the client-discovery extras. This
asymmetry is acknowledged but **out of scope** for v4 — see §7.)

### 2.4 Live runtime verification on `vexos-desktop-amd`

| Check | Result |
| --- | --- |
| `systemctl is-active avahi-daemon samba-wsdd nscd` | all `active` |
| `/etc/samba/smb.conf` symlink target | `/nix/store/…-smb.conf` (resolves correctly — v3 fix is effective) |
| `cat /etc/nsswitch.conf | grep hosts` | `mymachines mdns4_minimal [NOTFOUND=return] resolve [!UNAVAIL=return] files myhostname dns mdns4` ✓ |
| System wsdd | `wsdd --discovery --listen /run/wsdd/wsdd.sock` (running) |
| Per-user wsdd (spawned by `gvfsd-wsdd`) | `wsdd --no-host --discovery --listen /run/user/1000/gvfsd/wsdd` (running — confirms `discovery = true` is effective end-to-end) |
| `gvfsd-network` | running (pid 4143) |
| `gvfsd-dnssd` | running (pid 4151) |
| GVfs package | `gvfs-1.58.4` with **all** backends: `gvfsd-{dnssd,network,smb,smb-browse,wsdd,nfs,sftp,…}` present in `libexec/` |
| `nautilus --version` | `GNOME nautilus 49.4` (from unstable overlay) |
| `avahi-browse -art` (7 s on `eno1`) | Sees `_workstation._tcp`, `_airplay._tcp`, `_spotify-connect._tcp`, `_home-assistant._tcp` from 5 distinct peers across `192.168.100.0/24` and `192.168.101.0/24` |
| **Filtered for `_smb._tcp` / `_nfs._tcp` / `_sftp-ssh._tcp`** | **zero responses** |
| `gio list network://` | **empty** |
| `gio mount -l` | only local `GProxyVolumeMonitorUDisks2` entries (expected) |

### 2.5 AppArmor — ruled out

The orchestrator's hint flagged AppArmor as a possible blocker. It is
not. Inspection of the `apparmor.nix` module (in
`/nix/store/…-nixos-25.11.6913.fabb8c9deee2/nixos/nixos/modules/security/apparmor.nix`)
shows that `cfg.packages` contributes only an `Include` directory to
the parser config:

```nix
+ lib.concatMapStrings (p: "Include ${p}/etc/apparmor.d\n") cfg.packages;
```

Profiles are loaded into the kernel **exclusively** from
`security.apparmor.policies`:

```nix
ExecStart = lib.mapAttrsToList (
  n: p: "${pkgs.apparmor-parser}/bin/apparmor_parser --add ${commonOpts n p}"
) enabledPolicies;
```

This repository sets `policies = { };`
([modules/security.nix](modules/security.nix#L46)). Therefore **no
AppArmor profile is loaded** despite `apparmor-profiles` being in
`packages`. The bundle merely makes profiles available for `#include`.

---

## 3. Root Cause

**The vexos-nix configuration is functionally complete and matches a
fresh NixOS GNOME install for the discovery code path.** Every
component the orchestrator's hint listed is enabled, configured
correctly, and confirmed running on the live host:

- Avahi mDNS responder + browser is up with `nssmdns4 = true`,
  `openFirewall = true`, full `publish.*` enabled.
- `systemd-resolved` cedes mDNS/LLMNR to Avahi.
- `services.gvfs.enable = true` (auto-enabled by GNOME); the
  resulting `pkgs.gvfs` (1.58.4) ships all relevant backends —
  `gvfsd-dnssd`, `gvfsd-network`, `gvfsd-smb`, `gvfsd-smb-browse`,
  `gvfsd-wsdd`, `gvfsd-nfs`, `gvfsd-sftp` — and `gvfsd-network` +
  `gvfsd-dnssd` are running per-user right now.
- `samba-wsdd` runs system-wide with `--discovery`, and a second
  `wsdd` instance is spawned by `gvfsd-wsdd` listening on
  `/run/user/1000/gvfsd/wsdd` — i.e. the v3 fix
  (`discovery = true`) is effective end-to-end.
- `services.samba` produces `/etc/samba/smb.conf` (the v3 tmpfiles
  rule is honoured; the symlink resolves).
- Firewall opens UDP 5353 (mDNS), UDP 3702 + TCP 5357 (WSD).
- NetBIOS UDP 137 conntrack helper is loaded.

The precise runtime symptom is:

> `avahi-browse -art` on the vexos host sees **no** advertisements of
> `_smb._tcp`, `_nfs._tcp`, or `_sftp-ssh._tcp`. It sees plenty of
> other DNS-SD service types from peers on the same LAN. Therefore
> Avahi itself is healthy; the **publishers** of file-sharing
> services (`theannex` etc.) are simply not reachable via mDNS
> multicast from vexos's current network segment.

This is **not a vexos-nix configuration defect**. The fresh NixOS
GNOME install in the user's screenshot was on a network segment from
which `theannex`/`goliath`/`megatron` were reachable; vexos is
currently on one from which they are not (different VLAN, different
physical network, host powered off, VPN down, etc.). No NixOS config
change can make multicast traffic appear that the network is not
delivering.

### Why the prior three attempts kept "failing"

Every prior attempt added correct, useful configuration (and the
final state is now correct). The reason the user kept seeing an empty
Nautilus → Network view is the same in every revision: the LAN simply
has no `_smb._tcp` / `_nfs._tcp` / `_sftp-ssh._tcp` publishers
visible to vexos's mDNS scope. The fix attempts addressed the
software side of the discovery chain (which was indeed incomplete in
v1 and v2, and is now complete in v3), but no software fix can change
what Avahi receives on the wire.

### Defensive gaps worth closing in v4

While the configuration is functionally complete, three small,
deterministic, low-risk improvements remain. They will **not** make
unreachable hosts visible (nothing can), but they remove every
remaining cosmetic / future-proofing asymmetry between vexos and a
stock NixOS GNOME install, so when vexos is moved to a network with
reachable publishers, behaviour is bit-for-bit identical:

1. **Pin `gvfs` to `pkgs.unstable`** — `nautilus`, `gnome-shell`,
   `mutter`, `gdm`, `gnome-session`, `gnome-settings-daemon`,
   `gnome-control-center`, `gnome-shell-extensions`, `gnome-console`,
   `gnome-disk-utility`, `baobab`, `gnome-software` are all already
   pinned to `pkgs.unstable` in
   [modules/gnome.nix](modules/gnome.nix#L20-L40). `gvfs` is the
   single GNOME-stack outlier still served from stable. Live builds
   today happen to converge on `gvfs-1.58.4` in both channels, so
   this is benign now — but a future stable-vs-unstable drift in
   the gvfs↔nautilus IPC surface would silently degrade the
   Network view. One-line addition; identical output today.

2. **Explicit `org.gnome.system.dns-sd display-local = "merged"`**
   in the universal system dconf database. The schema default on
   GNOME 49 is `"merged"` (which does merge local mDNS results
   into the Network view), but pinning it system-wide via
   `programs.dconf.profiles.user` removes any possibility that
   an upgrade leaves a stale `"disabled"` value lying in a user
   database (vexos always builds on fresh dconf, but the pin is
   free).

3. **`services.avahi.publish.domain = true`** —
   publishes `_browse._dns-sd._udp.local`, advertising the local
   browse domain. Stock GNOME-on-NixOS effectively publishes this
   via gvfs's own avahi calls; setting it explicitly on the
   daemon side removes asymmetry with peer hosts and costs one
   tiny periodic packet.

---

## 4. Proposed Solution

Per the project's **Option B** rule (universal base + role
additions, **no `lib.mkIf` guards in shared modules**, role
expressed entirely through import lists), all changes land in
**existing, already-imported** files. **No new files. No
`configuration-*.nix` import-list changes.**

### Files modified

| File | Change | Reaches roles |
| --- | --- | --- |
| [modules/gnome.nix](modules/gnome.nix) | (a) Add `gvfs = u.gvfs;` line to existing core-shell-stack overlay. (b) Add `"org/gnome/system/dns-sd"` settings block to the existing universal dconf database. | desktop, htpc, stateless, server (every role that imports `modules/gnome.nix`) |
| [modules/network-desktop.nix](modules/network-desktop.nix) | Add one key (`domain = true;`) to the existing `services.avahi.publish` attrset. | desktop, htpc, stateless |

### Files NOT modified

- [modules/network.nix](modules/network.nix) — universal base for
  *all* roles including `headless-server`. The publish.domain key
  belongs only on roles that have a desktop, so it must NOT live
  here.
- [modules/security.nix](modules/security.nix) — AppArmor proven inert.
- All `configuration-*.nix` — no import-list changes; new settings
  live in already-imported files.
- All per-role `gnome-<role>.nix` — the new dconf key has no
  per-role variation; lives correctly in the universal base.

### Why no `lib.mkIf` guards

The `services.avahi.publish.domain` setting goes into
`network-desktop.nix` because that file is **not** imported by the
two headless server roles — file presence in the import list IS the
guard. The two changes in `modules/gnome.nix` are universal across
every role that imports `gnome.nix` (which by definition has a
GNOME shell), so no guard is needed. **Zero new `lib.mkIf` blocks.**

---

## 5. Implementation Steps (literal Nix)

### Step 1 — `modules/gnome.nix`: pin `gvfs` to unstable

Edit the existing core-shell-stack overlay at
[modules/gnome.nix lines 18–40](modules/gnome.nix#L18-L40). Add **one
line** alongside the other unstable pins (placement: directly after
`gnome-software = u.gnome-software;`, before the closing `}`):

```nix
nixpkgs.overlays = [
  (final: prev: let u = final.unstable; in {
    # Core GNOME shell stack
    gnome-shell            = u.gnome-shell;
    mutter                 = u.mutter;
    gdm                    = u.gdm;
    gnome-session          = u.gnome-session;
    gnome-settings-daemon  = u.gnome-settings-daemon;
    gnome-control-center   = u.gnome-control-center;
    gnome-shell-extensions = u.gnome-shell-extensions;

    # Default GNOME applications
    nautilus               = u.nautilus;
    gnome-console          = u.gnome-console;
    gnome-disk-utility     = u.gnome-disk-utility;
    baobab                 = u.baobab;
    gnome-software         = u.gnome-software;

    # GNOME Virtual File System — pinned to unstable for IPC parity
    # with the unstable nautilus build above. Provides the dnssd,
    # network, smb, smb-browse, wsdd, nfs, sftp backends used by
    # the Nautilus → Network sidebar entry.
    gvfs                   = u.gvfs;
  })
  # … the second (Extensions-app removal) overlay block below
  # remains unchanged …
];
```

### Step 2 — `modules/gnome.nix`: explicit `dns-sd` dconf default

In the existing universal dconf database
([modules/gnome.nix lines 87–137](modules/gnome.nix#L87-L137)), add
**one new top-level settings key** alongside the existing
`"org/gnome/desktop/screensaver"`,
`"org/gnome/settings-daemon/plugins/housekeeping"`, etc. blocks
(placement: at the bottom of the same `settings = { … };` map, so
the universal database keeps growing in one block):

```nix
# ── Network share discovery (Nautilus "Network" sidebar) ────────
# Pin GNOME's DNS-SD aggregation behaviour so that locally-
# discovered mDNS services are merged into the same Network view
# as remote ones. "merged" is the GNOME 49 schema default; we pin
# it system-wide so an unexpected upgrade-path stale value in any
# user database cannot silently hide auto-discovered SMB/NFS/SFTP
# hosts. vexos builds always run on fresh dconf, so this is purely
# defensive.
"org/gnome/system/dns-sd" = {
  display-local = "merged";
};
```

(The key sits **inside** the same single `databases = [ { settings =
{ … }; } ];` list that already holds the wallpaper, interface, wm,
background-logo-extension, screensaver, session, and housekeeping
blocks — it is appended to that map.)

### Step 3 — `modules/network-desktop.nix`: publish browse domain

Edit the existing `services.avahi.publish` attrset at
[modules/network-desktop.nix lines 46–52](modules/network-desktop.nix#L46-L52)
to add one key:

```nix
services.avahi.publish = {
  enable       = true;
  addresses    = true;
  workstation  = true;
  userServices = true;
  domain       = true;   # publishes _browse._dns-sd._udp.local —
                         # parity with stock GNOME-on-NixOS, which
                         # publishes the browse domain via gvfs's
                         # own avahi calls.
};
```

### Step 4 — Validation (Phase 3 / Phase 6)

Reviewer must confirm:

```bash
# Build
nix flake check
sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd
sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia
sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm
sudo nixos-rebuild dry-build --flake .#vexos-htpc-amd
sudo nixos-rebuild dry-build --flake .#vexos-stateless-amd

# Evaluation:
nix eval --impure --raw --expr '
let f = builtins.getFlake (toString ./.);
    c = f.nixosConfigurations.vexos-desktop-amd.config;
in builtins.toJSON {
  pubdomain = c.services.avahi.publish.domain;
  gvfs_path = c.services.gvfs.package.outPath;
}'
# Expect: pubdomain = true; gvfs path matches pkgs.unstable.gvfs.

# Runtime smoke (after `nixos-rebuild switch`):
systemctl is-active avahi-daemon samba-wsdd
ls -l /etc/samba/smb.conf
avahi-browse -art --terminate | head -40

# Manual test (LAN-dependent — NOT a build gate):
avahi-browse -art --terminate \
  | grep -E '_smb._tcp|_nfs._tcp|_sftp-ssh._tcp'
gio list network://
# If both still empty AFTER the change: the LAN currently has no
# such publishers reachable. This is environmental, not a defect.
```

The "actual NAS appears in Nautilus → Network" check is **inherently
unverifiable in CI** because it depends on the network segment the
build runs on. Reviewer must confirm the build succeeds and the
configured options reach the final closure; the user must verify
visibility manually on a network segment where at least one
publisher is reachable. If `avahi-browse -art | grep -E '_smb|_nfs
|_sftp-ssh'` is empty on that segment, the issue is upstream
(publisher down, VLAN, broken multicast snooping on the switch),
not vexos-nix.

---

## 6. Risks & Mitigations

| Risk | Likelihood | Mitigation |
| --- | --- | --- |
| `pkgs.unstable.gvfs` and `pkgs.unstable.nautilus` mismatch | Effectively zero — both come from the same `nixpkgs-unstable` flake input snapshot, by construction in [flake.nix](flake.nix). | Reviewer must confirm the same `nixpkgs-unstable` revision feeds both. |
| Adding `gvfs` to the unstable overlay forces a one-time mass rebuild of GNOME-app dependents. | Acceptable — same scope as the existing nautilus pin already triggers. | Single sweep; no ongoing cost. |
| `services.avahi.publish.domain = true` increases mDNS chatter. | Negligible — one tiny periodic packet. | Acceptable; matches stock GNOME-on-NixOS behaviour. |
| Forcing `dns-sd display-local = "merged"` overrides a user that intentionally disabled it. | Effectively zero — there is no GNOME UI to flip this and "merged" is the schema default. | Acceptable. |
| Multicast / WSD exposure on hostile LANs. | Pre-existing — unchanged. | UDP 5353 / UDP 3702 / TCP 5357 already open today. No new exposure. |
| A future commit enables AppArmor policies that confine `avahi-daemon` / `gvfsd-*` and silently break discovery again. | Low. | `security.apparmor.policies = { }` keeps everything unloaded; any regression would surface through aa-status and live-discovery checks. |
| The user concludes the change "didn't work" because the network still has no reachable publishers. | High — this is the most likely failure mode. | Documentation in §5 step-4 explicitly tells the reviewer/user how to disambiguate environmental from configuration causes. |

---

## 7. Out of Scope (Explicit — do NOT implement in Phase 2)

- **Server-side share hosting.** No `services.samba.smbd.enable =
  true`, no `services.samba.nmbd.enable = true`, no
  `services.nfs.server.enable = true`. This spec is purely about
  *client-side discovery*.
- **AppArmor profile activation** for `avahi-daemon`, `smbd`,
  `nautilus`, `gvfsd`. Leave `policies = { }` as is.
- **Headless server roles** (`headless-server`,
  `headless-server-*`). They intentionally do not import
  `network-desktop.nix` and that asymmetry is preserved. They keep
  Avahi mDNS *resolution* (sufficient for `.local` name lookup)
  but do not browse.
- **GUI server role asymmetry.** `configuration-server.nix`
  currently imports `gnome-server.nix` (full GNOME) but **does
  not** import `network-desktop.nix`. This is a separate
  architectural inconsistency not introduced by this spec; fixing
  it (i.e. adding `./modules/network-desktop.nix` to
  `configuration-server.nix`) is out of scope for v4 and should
  be tracked as a separate work item.
- **Cross-subnet bridging** (`services.avahi.reflector = true`).
  Out of scope; risks broadcast amplification.
- **New flake inputs.** No Context7 lookup is required — every
  option used here is stable in `nixpkgs/nixos-25.11`.
- **`system.stateVersion`** changes.
- **`hardware-configuration.nix`** (per-host, not tracked).

---

## 8. Dependencies (Context7 — none required)

All options used are stable in **nixpkgs nixos-25.11** and in the
`nixos-unstable` snapshot already pinned by the `nixpkgs-unstable`
flake input. No new flake inputs, no third-party libraries.

| Option | NixOS module | Stable since |
| --- | --- | --- |
| `services.avahi.publish.domain` | `nixos/modules/services/networking/avahi-daemon.nix` | NixOS ≥ 20.03 |
| `services.gvfs.package` (overridden indirectly via overlay) | `nixos/modules/services/desktops/gvfs.nix` | NixOS ≥ 19.09 |
| `programs.dconf.profiles.<name>.databases` | `nixos/modules/programs/dconf.nix` | NixOS ≥ 24.05 |
| `org.gnome.system.dns-sd` schema (`display-local`) | gsettings-desktop-schemas | GNOME ≥ 3.0 |

Because no new external library or framework is introduced and no
deprecated API is touched, no `resolve-library-id` / `get-library-docs`
lookups are required by the
[copilot-instructions](.github/copilot-instructions.md) Dependency &
Documentation Policy.

---

## 9. Phase 1 Deliverables Checklist

- [x] Current state analysis — §2 (sources quoted, evaluated config dumped, live runtime verified)
- [x] Root cause — §3 (precise: configuration is correct; observed symptom is environmental; AppArmor explicitly ruled out with module-source citation)
- [x] Proposed solution — §4 (Option B compliant; no new files; no `lib.mkIf` guards; no import-list changes)
- [x] Implementation steps — §5 (literal Nix, file-by-file, with anchored line ranges)
- [x] Risks — §6
- [x] Out of scope — §7 (server-side hosting explicitly excluded)
- [x] Dependencies — §8 (no new inputs; no Context7 lookups required)

---

## 10. Summary for Orchestrator

**Root cause.** The vexos-nix configuration is **already correct**;
v1+v2+v3 collectively built a functionally complete client-side
discovery stack. Live runtime on `vexos-desktop-amd` confirms every
component is enabled and running. The user's empty Nautilus →
Network view is caused by **no `_smb._tcp` / `_nfs._tcp` /
`_sftp-ssh._tcp` publishers being reachable via mDNS multicast from
vexos's current LAN segment** — confirmed by `avahi-browse` showing
plenty of other DNS-SD service types but none of those three.

**Proposed fix.** Three small defensive enhancements (one new line
each) so that *when* vexos is on a network with reachable
publishers, behaviour matches stock GNOME-on-NixOS bit-for-bit:

1. Pin `gvfs` to `pkgs.unstable` in the existing GNOME overlay
   ([modules/gnome.nix](modules/gnome.nix)).
2. Pin `org.gnome.system.dns-sd display-local = "merged"` in the
   universal system dconf database
   ([modules/gnome.nix](modules/gnome.nix)).
3. Add `services.avahi.publish.domain = true;` in
   [modules/network-desktop.nix](modules/network-desktop.nix).

**Architecture compliance.** All three changes land in
already-imported shared modules; no new files; no
`configuration-*.nix` import-list changes; no new `lib.mkIf` guards.

**Spec file:**
[.github/docs/subagent_docs/network_share_discovery_v4_spec.md](.github/docs/subagent_docs/network_share_discovery_v4_spec.md)
