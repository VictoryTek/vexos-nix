# NAS Phase C — Add `cockpit-file-sharing` Plugin with Samba Registry Mode and NFS Server

**Project:** vexos-nix (NixOS 25.11 personal flake, `nixpkgs` pinned to
`github:NixOS/nixpkgs/nixos-25.11` rev `0c88e1f2bdb93d5999019e99cb0e61e1fe2af4c5`)
**Phase:** C of the NAS feature (file-sharing plugin)
**Status:** Specification — implementation pending
**Date:** 2026-05-11
**Authoring agent:** Phase 1 Research & Specification subagent

---

## 0. Phase scope reminder (read first)

This spec covers **Phase C only**:

> Add a new `vexos.server.cockpit.fileSharing.enable` sub-option to
> `modules/server/cockpit.nix`. When true it:
> 1. Installs the 45Drives `cockpit-file-sharing` plugin (pre-built,
>    extracted from the upstream Debian release `.deb`)
> 2. Enables `services.samba` in registry mode so the plugin can
>    create/edit/delete shares at runtime via `net conf`
> 3. Enables `services.nfs.server` so the NFS exports tab is functional

Out of scope for Phase C: ZFS plugin (`cockpit-zfs`, deferred since Phase B),
`cockpit-identities` (Phase D), the unified `vexos.server.nas.enable` umbrella
option (Phase D), iSCSI management, S3/MinIO management, Samba Active Directory
domain controller mode, Samba WSDD/Avahi advertisement, and Python venv
setup for S3 features.

---

## 1. Headline findings (READ THIS FIRST)

| Question | Finding | Source |
|---|---|---|
| `pkgs.cockpit-file-sharing` in nixpkgs at pinned rev? | **DOES NOT EXIST** — zero code results in `NixOS/nixpkgs`, absent from search.nixos.org for both 25.11 and unstable | GitHub code search; search.nixos.org |
| Upstream build system type? | **Yarn Berry v4.9.3 + `workspace:` protocols + `houston-common` git submodule** — identical Phase B blocker | `package.json` at `v4.5.6-1`; bootstrap.sh |
| Can we build from source in Nix sandbox? | **No** — same reason as Phase B: workspace: deps require network resolution that Nix forbids in the sandbox | Phase B spec; Phase B lesson |
| Alternative to source build? | **Yes — extract pre-built assets from the upstream `.deb` release** (architecture-independent, statically built JS/HTML/CSS, no compilation step) | `.deb` asset listing; `postinst` analysis |
| Python dependencies needed for Samba+NFS? | **No** — only `awscurl` (for S3 management, out of scope); Samba+NFS tabs work via shell commands | `requirements.txt` = `awscurl` only |
| Samba `configText` / `extraConfig` available? | **Both removed** at pinned rev — replaced by `services.samba.settings` (structured INI attrset) | `samba.nix` source at pinned rev |
| Samba registry mode syntax? | `services.samba.settings.global."include" = "registry"` in the `[global]` section | Upstream README; smb.conf(5) |
| NFS options exist? | Yes — `services.nfs.server.enable`, `services.nfs.server.exports`, `services.nfs.server.lockdPort`, etc. | search.nixos.org |

### What Phase C actually does, in one paragraph

Add `pkgs/cockpit-file-sharing/default.nix` that uses `fetchurl` to download
the upstream Debian Bookworm `.deb` for `cockpit-file-sharing v4.5.6-1`, then
`dpkg-deb -x` to extract the pre-built web assets from
`usr/share/cockpit/file-sharing/` into `$out/share/cockpit/file-sharing/`.
Register this under `pkgs.vexos.cockpit-file-sharing` via `pkgs/default.nix`.
Then add a `vexos.server.cockpit.fileSharing.enable` sub-option to
`modules/server/cockpit.nix` that, when true, installs the plugin package and
configures `services.samba` (with `include = registry` global setting and
`openFirewall = true`) plus `services.nfs.server.enable = true` with NFS firewall
ports. A fail-fast `assertion` guards that `vexos.server.cockpit.enable` is also
true. No new flake inputs. No changes to `flake.nix`.

---

## 2. Current-state analysis

### 2.1 Phase A and B overlay scaffolding is in place

`flake.nix` defines:
```nix
customPkgsOverlayModule = {
  nixpkgs.overlays = [ (import ./pkgs) ];
};
```
…wired into every `nixosConfiguration` role's `baseModules`.

`pkgs/default.nix` currently exposes one attribute:
```nix
final: prev: {
  vexos = (prev.vexos or { }) // {
    cockpit-navigator = final.callPackage ./cockpit-navigator { };
  };
}
```
Phase C adds one more entry (`cockpit-file-sharing`) using the same
`(prev.vexos or { }) //` accumulator pattern — no structural change.

### 2.2 `pkgs/cockpit-navigator/default.nix` is the style precedent

The Phase A derivation uses `stdenvNoCC.mkDerivation` + `fetchFromGitHub` +
`dontBuild = true` (static copy only). Phase C differs in source (we `fetchurl`
a `.deb`) but mirrors the same `stdenvNoCC`, `dontConfigure`, no build step
spirit. The install step uses `dpkg-deb -x` instead of `cp`.

### 2.3 `modules/server/cockpit.nix` already uses a `lib.mkMerge` pattern

Phase A's final `cockpit.nix` has two `lib.mkMerge` fragments:
1. `lib.mkIf cfg.enable` — enables the `services.cockpit` daemon
2. `lib.mkIf (cfg.enable && cfg.navigator.enable)` — installs
   `pkgs.vexos.cockpit-navigator`

Phase C adds a third fragment:
```nix
(lib.mkIf cfg.fileSharing.enable { ... })
```
guarded only by `cfg.fileSharing.enable` (which has a fail-fast assertion
that `cfg.enable` must also be true — the assertion is cleaner than a
compound conditional).

### 2.4 Samba options at the pinned rev

`nixos/modules/services/network-filesystems/samba.nix` at rev
`0c88e1f2bdb93d5999019e99cb0e61e1fe2af4c5` confirms:

- **Removed**: `services.samba.configText`, `services.samba.extraConfig`
  (both emit `mkRemovedOptionModule` evaluation errors)
- **Active**: `services.samba.settings` — a `freeformType` INI attrset whose
  `[global]` section has typed sub-options for `security`, `invalid users`, and
  `passwd program`, plus freeform string keys for everything else
- **Generated path**: `environment.etc."samba/smb.conf".source = configFile`
  (symlink from `/etc/samba/smb.conf` to a store path)
- **openFirewall**: opens TCP 139, 445 and UDP 137, 138 when true
- **winbindd.enable**: defaults to `true` (can be left at default; it doesn't
  interfere with basic file-sharing)

### 2.5 NFS options at the pinned rev

Options confirmed via search.nixos.org (25.11 channel, closest data point):
- `services.nfs.server.enable` — starts `nfsd`, `rpcbind`, `mountd`
- `services.nfs.server.exports` — string content of `/etc/exports`
- `services.nfs.server.lockdPort`, `mountdPort`, `statdPort` — optional fixed
  ports (useful for firewall)
- `networking.firewall.allowedTCPPorts` / `allowedUDPPorts` — needed for NFS
  ports (2049, 111)

---

## 3. The `cockpit-file-sharing` upstream plugin

### 3.1 Repository and version

- **Repo**: `https://github.com/45Drives/cockpit-file-sharing`
- **Latest stable release**: `v4.5.6-1` (tag: `v4.5.6-1`, commit `8e0616d`,
  released 3 weeks before spec date)
- **License**: GPL-3.0+

### 3.2 Build system analysis — why source build is infeasible

`package.json` at `v4.5.6-1`:
```json
{
  "private": true,
  "workspaces": [
    "file-sharing",
    "houston-common",
    "houston-common/houston-common-*"
  ],
  "packageManager": "yarn@4.9.3"
}
```

The repo is a **Yarn Berry v4.9.3 monorepo** with three workspace members
(the main plugin, and the `houston-common` git submodule at two nesting
levels). `bootstrap.sh` does:
```bash
jq 'del(.packageManager)' ./package.json | sponge ./package.json
rm .yarnrc.yml .yarn -rf
yarn set version stable
yarn config set nodeLinker node-modules
```
This is byte-for-byte the same bootstrapping pattern documented as infeasible
in the Phase B spec. During a Nix sandbox build:
1. `yarn set version stable` downloads the Berry runtime — **network access
   forbidden in sandbox**
2. Even if bootstrapped offline, `workspace:` protocol inter-package
   resolution requires the full monorepo tree including the `houston-common`
   git submodule (a recursive `fetchSubmodules = true` fetch resolves the
   file presence, but the yarn workspace resolution still downloads per-package
   caches from the network)

**Verdict**: Source build is not feasible with standard Nix tooling.

### 3.3 Alternative: extract from the upstream pre-built `.deb`

The upstream CI publishes architecture-independent `.deb` packages for each
release. These contain the already-built frontend bundle (Vite output) plus the
plugin manifest. They require **no runtime compilation** and are pure static
web assets + shell scripts.

**`packaging/debian-bookworm/postinst`** (what the `.deb` does after install):
```sh
PLUGIN_DIR="/usr/share/cockpit/file-sharing"
VENV_DIR="$PLUGIN_DIR/venv"
if [ "$1" = "configure" ] || [ "$1" = "triggered" ]; then
  if command -v python3 >/dev/null 2>&1; then
    python3 -m venv "$VENV_DIR" 2>/dev/null || :
    if [ -x "$VENV_DIR/bin/pip" ]; then
      "$VENV_DIR/bin/pip" install --upgrade pip || :
      "$VENV_DIR/bin/pip" install -r "$PLUGIN_DIR/requirements.txt" || :
    fi
  fi
fi
exit 0
```
The `postinst` only sets up a Python venv for `awscurl` (S3 management). For
our Samba + NFS scope, this step is unnecessary and we skip it entirely.

**`.deb` internal layout** (inferred from Makefile + Debian packaging scripts):
```
usr/
  share/
    cockpit/
      file-sharing/
        manifest.json        ← Cockpit plugin descriptor
        favicon.ico
        requirements.txt     ← "awscurl" (S3 only, skipped)
        index.html           ← Vite-built frontend entry
        assets/              ← Compiled JS, CSS bundles
```
The `manifest.json` declares the plugin to Cockpit's XDG_DATA_DIRS scan,
exactly as Phase A's `cockpit-navigator/manifest.json` does.

**`.deb` download URL for `v4.5.6-1` (Debian Bookworm)**:
```
https://github.com/45Drives/cockpit-file-sharing/releases/download/v4.5.6-1/cockpit-file-sharing_4.5.6-1bookworm_all.deb
```

> **Note for implementation agent**: The `sha256` hash must be computed during
> implementation using:
> ```bash
> nix-hash --type sha256 --base64 <(curl -fsSL <url>)
> # or:
> nix store prefetch-file <url>
> ```
> Use the SRI-format hash (`sha256-...`) in the `hash =` field.

### 3.4 Runtime dependencies

| Dependency | Purpose | Source on NixOS |
|---|---|---|
| `net` binary | Samba registry management (`net conf`) | `pkgs.samba` (must be in `environment.systemPackages`) |
| `smbpasswd` | Samba user password management | Same `pkgs.samba` package |
| `exportfs` | NFS exports management | `pkgs.nfs-utils` (pulled in by `services.nfs.server.enable = true`) |
| `cockpit-bridge` | Cockpit JS ↔ host bridge | Handled by `services.cockpit.enable = true` |
| `coreutils`, `attr`, `findutils` | Shell utilities used by plugin scripts | Part of NixOS base system |

The `net` and `smbpasswd` binaries from `pkgs.samba` are **not** automatically
placed on `$PATH` by `services.samba.enable = true` (the module uses the store
path directly in systemd unit `ExecStart=` lines). We must add `pkgs.samba`
to `environment.systemPackages` explicitly.

### 3.5 NFS management approach

The plugin's NFS tab edits
`/etc/exports.d/cockpit-file-sharing.exports`, which has the same syntax as
`/etc/exports`. The Linux kernel NFS server (`nfsd`) includes all files from
`/etc/exports.d/*.exports` in addition to `/etc/exports`. This is a clean
separation:

- NixOS manages `/etc/exports` via `services.nfs.server.exports` (immutable
  store symlink)
- The plugin manages `/etc/exports.d/cockpit-file-sharing.exports` (writable
  file, not Nix-managed)

The `/etc/exports.d/` directory may not exist by default. We create it via
`systemd.tmpfiles.rules`. The plugin calls `exportfs -r` after each change,
which reloads all exports including the plugin-managed file.

### 3.6 Samba registry mode — deep dive

**How Cockpit file-sharing manages Samba shares**:
The Samba tab is "a front end UI for the `net conf` registry used by Samba".
The plugin calls `net conf setparm`, `net conf addshare`, `net conf delshare`
etc. to write share definitions into Samba's TDB registry database (stored in
`/var/lib/samba/private/registry.tdb`).

**The required smb.conf entry**:
```ini
[global]
    include = registry
```
This single line instructs smbd to load share definitions from the TDB
registry in addition to the static smb.conf. NixOS generates smb.conf as a
store-path symlink — immutable — but the TDB registry is a mutable file in
`/var/lib/samba/`. They do not conflict.

**NixOS Samba module (at pinned rev) — key facts**:
1. `services.samba.settings.global` is an attrset where `security`, `passwd
   program`, and `invalid users` are typed options; all other keys are freeform
   strings. Setting `"include" = "registry"` adds a new freeform key.
2. `services.samba.settings` defaults already set `security = "user"`,
   `passwd program = "/run/wrappers/bin/passwd %u"`, `invalid users = ["root"]`.
   We only need to ADD the `"include"` key — no need to repeat defaults.
3. The TDB registry is auto-initialized by smbd on first start. No activation
   script is needed.
4. `services.samba.openFirewall = true` opens TCP 139, 445 and UDP 137, 138.

---

## 4. Option design

### 4.1 New option: `vexos.server.cockpit.fileSharing.enable`

```nix
fileSharing.enable = lib.mkOption {
  type = lib.types.bool;
  default = cfg.enable;
  description = ''
    Install the 45Drives cockpit-file-sharing plugin and configure
    Samba (registry mode) + NFS server for GUI-managed file sharing.
    Defaults to the value of vexos.server.cockpit.enable.
    Requires vexos.server.cockpit.enable = true (enforced by assertion).
  '';
};
```

**Default = `cfg.enable`**: Mirrors the `navigator.enable` precedent — opting
into Cockpit also opts into the file-sharing plugin. The operator can set
`vexos.server.cockpit.fileSharing.enable = false` to opt out.

### 4.2 Assertion

```nix
{
  assertion = cfg.fileSharing.enable -> cfg.enable;
  message = ''
    vexos.server.cockpit.fileSharing.enable = true requires
    vexos.server.cockpit.enable = true.
  '';
}
```

---

## 5. Architecture — Option B compliance

This project uses **Option B: common base + role additions**. Phase C changes
are restricted to:

- `pkgs/cockpit-file-sharing/default.nix` — new file, package derivation only
- `pkgs/default.nix` — add one line to the `vexos` attrset
- `modules/server/cockpit.nix` — extend existing option set and `lib.mkMerge`

No `lib.mkIf` guards by role. The `modules/server/cockpit.nix` is already
imported only by server/headless-server roles (via `modules/server/default.nix`
→ `modules/server/cockpit.nix`). This means the option is available but
inactive on non-server roles, which is the correct Option B behavior.

---

## 6. Implementation steps (ordered, file-by-file)

### Step 1 — Get the `.deb` SHA256 hash

On a Linux host with Nix installed, run:
```bash
nix store prefetch-file \
  https://github.com/45Drives/cockpit-file-sharing/releases/download/v4.5.6-1/cockpit-file-sharing_4.5.6-1bookworm_all.deb
```
Record the SRI-format hash (`sha256-...`) output.

### Step 2 — Create `pkgs/cockpit-file-sharing/default.nix`

```nix
# pkgs/cockpit-file-sharing/default.nix
# 45Drives cockpit-file-sharing — Samba + NFS share management plugin for
# the Cockpit web admin UI.  Ships as pure static JS/HTML/CSS built by
# upstream CI; we extract the pre-built assets from the official Debian
# release package rather than attempting a Yarn Berry v4 monorepo build
# (which is infeasible in the Nix sandbox — same reason cockpit-zfs was
# deferred in Phase B).
#
# Installed to $out/share/cockpit/file-sharing/ so Cockpit's XDG_DATA_DIRS
# scan discovers the plugin's manifest.json automatically (same pattern as
# cockpit-navigator; see Phase A spec for details).
#
# Python venv (awscurl, for S3 management) is deliberately skipped —
# Samba + NFS tabs work via shell commands (net conf, exportfs) only.
{ lib, stdenvNoCC, fetchurl, dpkg }:

stdenvNoCC.mkDerivation rec {
  pname = "cockpit-file-sharing";
  version = "4.5.6";
  release = "1";

  src = fetchurl {
    url = "https://github.com/45Drives/cockpit-file-sharing/releases/download/v${version}-${release}/cockpit-file-sharing_${version}-${release}bookworm_all.deb";
    hash = "sha256-PLACEHOLDER";  # replace with output of: nix store prefetch-file <url>
  };

  nativeBuildInputs = [ dpkg ];

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    dpkg-deb -x "$src" extracted
    mkdir -p "$out/share/cockpit"
    cp -r extracted/usr/share/cockpit/file-sharing "$out/share/cockpit/"
    runHook postInstall
  '';

  meta = with lib; {
    description = "Samba and NFS share management plugin for the Cockpit web admin UI (45Drives)";
    homepage = "https://github.com/45Drives/cockpit-file-sharing";
    license = licenses.gpl3Only;
    platforms = platforms.linux;
    maintainers = [ ];
  };
}
```

### Step 3 — Extend `pkgs/default.nix`

Add `cockpit-file-sharing` to the `vexos` attrset:

```nix
# pkgs/default.nix
final: prev: {
  vexos = (prev.vexos or { }) // {
    cockpit-navigator  = final.callPackage ./cockpit-navigator { };
    cockpit-file-sharing = final.callPackage ./cockpit-file-sharing { };
  };
}
```

### Step 4 — Extend `modules/server/cockpit.nix`

Add the new option declaration to `options.vexos.server.cockpit` and a third
`lib.mkMerge` fragment to `config`. The complete final file:

```nix
# modules/server/cockpit.nix
# Cockpit — web-based Linux server management UI, plus optional
# 45Drives plugin sub-options.
#
# Plugin discovery: Cockpit at the pinned nixpkgs rev does NOT expose a
# services.cockpit.plugins option (that machinery post-dates this pin).
# Plugins are surfaced via XDG_DATA_DIRS — any package on
# environment.systemPackages whose $out/share/cockpit/<name>/manifest.json
# exists is auto-discovered, because the cockpit module itself sets
# environment.pathsToLink = [ "/share/cockpit" ]. See:
#   .github/docs/subagent_docs/nas_phase_a_cockpit_navigator_spec.md
#
# NOTE: cockpit-zfs (Phase B) is deferred — upstream v1.2.26 uses a
# Yarn Berry v4 monorepo with unresolved workspace: deps in the zfs/
# package-lock.json, making sandbox builds infeasible without upstream
# changes. Revisit when cockpit-zfs lands in nixpkgs or upstream ships
# a self-contained lockfile.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.cockpit;
in
{
  options.vexos.server.cockpit = {
    enable = lib.mkEnableOption "Cockpit web management console";

    port = lib.mkOption {
      type = lib.types.port;
      default = 9090;
      description = "Port for the Cockpit web interface.";
    };

    navigator.enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable;
      description = ''
        Install the 45Drives cockpit-navigator file-browser plugin.
        Defaults to the value of vexos.server.cockpit.enable so that
        enabling Cockpit also installs Navigator (the simplest plugin)
        — set to false to opt out, or to true on its own to stage the
        package without enabling Cockpit (no effect at runtime).
      '';
    };

    fileSharing.enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable;
      description = ''
        Install the 45Drives cockpit-file-sharing plugin and configure
        Samba (registry mode) + NFS server for GUI-managed file sharing.
        Defaults to the value of vexos.server.cockpit.enable.
        Requires vexos.server.cockpit.enable = true (enforced by assertion).
      '';
    };

  };

  config = lib.mkMerge [

    # ── Base Cockpit daemon ────────────────────────────────────────────────
    (lib.mkIf cfg.enable {
      services.cockpit = {
        enable = true;
        port = cfg.port;
        openFirewall = true;
      };
    })

    # ── Navigator plugin ───────────────────────────────────────────────────
    (lib.mkIf (cfg.enable && cfg.navigator.enable) {
      environment.systemPackages = [ pkgs.vexos.cockpit-navigator ];
    })

    # ── File-sharing plugin (Samba + NFS) ──────────────────────────────────
    (lib.mkIf cfg.fileSharing.enable {

      assertions = [
        {
          assertion = cfg.fileSharing.enable -> cfg.enable;
          message = ''
            vexos.server.cockpit.fileSharing.enable = true requires
            vexos.server.cockpit.enable = true.
          '';
        }
      ];

      # Plugin package — provides /share/cockpit/file-sharing/manifest.json
      # which Cockpit auto-discovers via environment.pathsToLink.
      environment.systemPackages = [
        pkgs.vexos.cockpit-file-sharing
        # samba package needed for 'net' (registry management) and 'smbpasswd'
        # on $PATH. services.samba.enable does not add these to systemPackages.
        pkgs.samba
      ];

      # ── Samba — registry mode ─────────────────────────────────────────────
      # The file-sharing plugin manages shares via 'net conf' commands, which
      # write to Samba's TDB registry (not to smb.conf). The 'include =
      # registry' line in [global] tells smbd to load share definitions from
      # the registry at startup — the NixOS-generated smb.conf (immutable
      # store symlink) and the mutable TDB registry coexist without conflict.
      #
      # configText and extraConfig are removed at the pinned rev; use settings.
      services.samba = {
        enable = true;
        openFirewall = true;  # TCP 139, 445; UDP 137, 138
        settings.global = {
          "include" = "registry";
        };
      };

      # ── NFS — server enabled, exports managed by plugin ───────────────────
      # The plugin writes to /etc/exports.d/cockpit-file-sharing.exports.
      # NixOS manages /etc/exports (symlink); /etc/exports.d/ is separate.
      # nfsd reads both locations when exportfs -r is invoked by the plugin.
      services.nfs.server.enable = true;

      # /etc/exports.d/ may not exist by default; create it as a writable dir.
      systemd.tmpfiles.rules = [
        "d /etc/exports.d 0755 root root -"
      ];

      # NFS firewall ports: 2049 (nfsd), 111 (rpcbind/portmapper).
      # lockd/mountd/statd use ephemeral ports by default; pin them if the
      # host firewall is restrictive (operator concern, not defaulted here).
      networking.firewall = {
        allowedTCPPorts = [ 2049 111 ];
        allowedUDPPorts = [ 2049 111 ];
      };

    })

  ];
}
```

---

## 7. Testing plan

### 7.1 Derivation eval check (Windows + WSL, no Linux rebuild needed)

```bash
# Verify the new overlay attribute evaluates:
wsl -- bash -lc "
  cd /mnt/c/Projects/vexos-nix
  nix-instantiate --eval --strict -E \
    '(import <nixpkgs> { overlays = [ (import ./pkgs) ]; }).vexos.cockpit-file-sharing.drvPath'
  2>&1
"
```
Expected output: a `/nix/store/...` drv path (no eval errors).

### 7.2 Derivation build check (Linux host with network access)

```bash
nix-build --no-out-link -E \
  '(import <nixpkgs> { overlays = [ (import ./pkgs) ]; }).vexos.cockpit-file-sharing'
```
Expected: successful build; verify `result/share/cockpit/file-sharing/manifest.json`
exists.

### 7.3 Flake check (deferred to Phase 6 preflight on Linux host)

```bash
nix flake check
sudo nixos-rebuild dry-build --flake .#vexos-server-amd
sudo nixos-rebuild dry-build --flake .#vexos-headless-server-amd
```
These are the roles that import `modules/server/cockpit.nix`. The option is
inactive (`enable = false`) by default so all non-server roles are unaffected.

### 7.4 Manual smoke test (on a running NixOS server)

1. Add to `/etc/nixos/server-services.nix`:
   ```nix
   vexos.server.cockpit.enable = true;
   # fileSharing.enable defaults to true when cockpit.enable = true
   ```
2. Run `sudo nixos-rebuild switch --flake .#vexos-server-amd`
3. Open `https://<server>:9090` → verify "File Sharing" tab appears
4. In the Samba tab: create a share `/srv/test-share` → verify `net conf list`
   shows the share
5. Confirm `smbd` continues running: `systemctl status samba-smbd`
6. In the NFS tab: create an export `/srv/nfs-test 192.168.1.0/24(rw)` →
   verify `/etc/exports.d/cockpit-file-sharing.exports` was created

---

## 8. Samba registry mode — detailed rationale

### 8.1 How the NixOS smb.conf generation works

At the pinned rev, `nixos/modules/services/network-filesystems/samba.nix`:
1. Generates a structured INI file from `services.samba.settings` using
   `pkgs.formats.ini`
2. Writes it to the Nix store as `smb.conf`
3. Symlinks it: `environment.etc."samba/smb.conf".source = configFile`
4. Sets `restartTriggers = [ configFile ]` on `samba-smbd.service`

Result: `/etc/samba/smb.conf` is a symlink to an immutable store path.

### 8.2 How `include = registry` coexists with the immutable smb.conf

`include = registry` is a Samba global parameter that instructs smbd to
additionally load share definitions from the TDB registry database at
`/var/lib/samba/private/registry.tdb`. This registry:
- Is a **mutable** binary TDB file (not in the Nix store)
- Is **auto-initialized** by `net conf` or smbd on first start
- Is **written to** by the cockpit-file-sharing plugin via:
  - `net conf addshare <name> <path>` — creates a share
  - `net conf setparm <name> <key> <value>` — sets a share parameter
  - `net conf delshare <name>` — removes a share
  - `net conf list` — reads current shares (used by the plugin UI)

The immutable smb.conf and the mutable TDB registry are **orthogonal**:
- smb.conf provides: global settings (security mode, invalid users, etc.)
- Registry provides: per-share definitions (managed by the GUI)

smbd merges both on startup. Share edits via the GUI take effect immediately
(smbd detects registry changes without a full restart).

### 8.3 Minimum-viable Samba config

```nix
services.samba = {
  enable = true;
  openFirewall = true;
  settings.global = {
    "include" = "registry";
  };
};
```

The NixOS module's default `settings.global` already sets:
```nix
security = "user";
"passwd program" = "/run/wrappers/bin/passwd %u";
"invalid users" = [ "root" ];
```
We only add the `"include"` key; all defaults are preserved. No shares are
declared in Nix (they are managed by the GUI at runtime).

### 8.4 The `net` binary on PATH

The `pkgs.samba` package provides `/nix/store/.../bin/net`. The
`services.samba.enable = true` wires up systemd units but does NOT add `net`
to `$PATH`. The Cockpit plugin forks shell commands to call `net conf ...`.
For these to work, `pkgs.samba` must be in `environment.systemPackages`.

---

## 9. NFS management — detailed rationale

### 9.1 Two-file separation

| File | Manager | Content |
|---|---|---|
| `/etc/exports` | NixOS (`services.nfs.server.exports`) | Static; may be empty string if no static exports needed |
| `/etc/exports.d/cockpit-file-sharing.exports` | cockpit-file-sharing plugin | Dynamic; created/edited by GUI |

The `exportfs` utility (part of `nfs-utils`, brought in by
`services.nfs.server.enable = true`) reads both `/etc/exports` and all files
matching `/etc/exports.d/*.exports`. The plugin calls `exportfs -r` after each
GUI change, which reloads both.

### 9.2 The `/etc/exports.d/` directory

This directory is NOT guaranteed to exist on a freshly installed NixOS system.
`systemd.tmpfiles.rules = [ "d /etc/exports.d 0755 root root -" ]` creates it
idempotently on every boot (tmpfiles rules run before other services).

### 9.3 NFS firewall

- Port **2049/tcp** and **2049/udp** — NFSv4 main port and NFSv3 nfsd
- Port **111/tcp** and **111/udp** — `rpcbind` (portmapper, required for
  NFSv3 auxiliary services like `mountd` and `statd`)
- `lockdPort`, `mountdPort`, `statdPort` — left at ephemeral (OS-assigned)
  in this spec; the operator may pin them if the server's external firewall
  is stateless and cannot track ephemeral ports

---

## 10. Risks and mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| `.deb` URL format changes in future releases | Low (45Drives has used this format since v3.x) | Pin to `v4.5.6-1`; update version+hash when upgrading |
| `.deb` content layout differs from expected (`usr/share/cockpit/file-sharing/`) | Very low (confirmed from packaging scripts and Makefile) | Verify with `dpkg-deb --contents <file.deb>` during implementation |
| `dpkg-deb` not available in sandbox | None — `dpkg` is in nixpkgs and listed in `nativeBuildInputs` | Use `nativeBuildInputs = [ dpkg ]` as specified |
| Samba TDB registry not initialized before first `net conf` call | Low — smbd initializes the registry on first start | `services.samba.enable = true` starts smbd; registry is ready |
| NixOS `smb.conf` rebuild (on nixos-rebuild switch) clobbers registry-written share state | **None** — registry and smb.conf are separate; `restartTriggers` restarts smbd but does NOT wipe the TDB registry | Verified by architecture: TDB is a persistent file in `/var/lib/samba/` |
| `winbindd` (enabled by default) conflicts with file-sharing use case | Very low — winbindd provides NSS and PAM for domain accounts; it doesn't interfere with local share management | Leave at default; operator can disable if desired |
| `/etc/exports.d/` created by tmpfiles but removed by `nixos-rebuild` | None — `environment.etc` only manages explicitly declared entries; `/etc/exports.d/` is unmanaged by Nix | Confirmed: Nix only symlinks declared `etc.*` entries |
| `cockpit-file-sharing` iSCSI or S3 tabs fail at runtime | Expected — these features need SCST kernel module or boto3 venv, neither installed | Out of scope; tabs will show graceful "service not available" messages |

---

## 11. Forward-compatibility (Phase D)

Phase D will add `cockpit-identities` and a unified `vexos.server.nas.enable`
umbrella option. Phase C's design is forward-compatible because:

1. **Option namespace is extensible**: `vexos.server.cockpit` already has
   `navigator.enable`, `fileSharing.enable`, and (deferred) a future
   `zfs.enable`. Phase D can add `identities.enable` with the same pattern.
2. **No structural coupling**: Phase C's Samba config (`services.samba.settings`)
   uses `lib.mkMerge` fragments; Phase D can add more Samba settings (e.g.,
   workgroup, realm for AD) in a separate `lib.mkMerge` fragment without
   touching Phase C's code.
3. **The NFS config is minimal**: Phase D's identities plugin does not touch NFS.
4. **`vexos.server.nas.enable`**: Phase D can set
   `vexos.server.cockpit.enable = true`,
   `vexos.server.cockpit.fileSharing.enable = true`, and
   `vexos.server.cockpit.identities.enable = true` (if implemented) as a
   single composite option, overriding the sub-options with `lib.mkDefault`.

---

## 12. Files implementation will create / modify

| Action | File path |
|---|---|
| **Create** | `pkgs/cockpit-file-sharing/default.nix` |
| **Modify** | `pkgs/default.nix` |
| **Modify** | `modules/server/cockpit.nix` |

No changes to `flake.nix`, `configuration-*.nix`, or any `hosts/` file.

---

## 13. References

1. **45Drives/cockpit-file-sharing — releases page** (latest: v4.5.6-1, 3 weeks ago):
   `https://github.com/45Drives/cockpit-file-sharing/releases`

2. **45Drives/cockpit-file-sharing — README.md (v4.5.6-1) — Samba registry mode**:
   > "The Samba tab in cockpit-file-sharing is a front end UI for the `net conf`
   > registry used by Samba. … Your Samba configuration file must have
   > `include = registry` in the `[global]` section."
   `https://github.com/45Drives/cockpit-file-sharing/tree/v4.5.6-1`

3. **45Drives/cockpit-file-sharing — `package.json` at v4.5.6-1** — confirms
   Yarn Berry v4.9.3 + workspace monorepo:
   `https://github.com/45Drives/cockpit-file-sharing/blob/v4.5.6-1/package.json`

4. **NixOS `samba.nix` at pinned rev** — confirms `configText`/`extraConfig` removed;
   `settings` is the active option; `openFirewall` opens SMB ports:
   `https://github.com/NixOS/nixpkgs/blob/0c88e1f2bdb93d5999019e99cb0e61e1fe2af4c5/nixos/modules/services/network-filesystems/samba.nix`

5. **NixOS Wiki — Samba** — confirms `services.samba.settings.global` freeform
   key usage, `openFirewall`, `environment.systemPackages` for CLI tools:
   `https://wiki.nixos.org/wiki/Samba`

6. **NixOS options search — `services.nfs`** — confirms `services.nfs.server.enable`,
   `services.nfs.server.exports`, `lockdPort`, `mountdPort`, `statdPort` at 25.11:
   `https://search.nixos.org/options?channel=25.11&query=services.nfs`

7. **search.nixos.org — `cockpit-file-sharing`** — confirms absence from both
   25.11 and unstable nixpkgs channels:
   `https://search.nixos.org/packages?channel=unstable&query=cockpit-file-sharing`

8. **NAS Phase B spec** (internal) — establishes Yarn Berry workspace: protocol
   failure mode and the proven plugin-discovery pattern used in Phase C:
   `c:\Projects\vexos-nix\.github\docs\subagent_docs\nas_phase_b_cockpit_zfs_spec.md`

9. **NAS Phase A spec** (internal) — establishes the `stdenvNoCC + static copy`
   derivation pattern, `lib.mkMerge` cockpit module structure, and
   `environment.pathsToLink = ["/share/cockpit"]` plugin discovery mechanism:
   `c:\Projects\vexos-nix\.github\docs\subagent_docs\nas_phase_a_cockpit_navigator_spec.md`

10. **Samba smb.conf(5) — `include = registry`**:
    `https://www.samba.org/samba/docs/current/man-html/smb.conf.5.html`

---

## 14. Blocker assessment

| Potential blocker | Status |
|---|---|
| Yarn Berry source build infeasible | ✅ Bypassed — use pre-built `.deb` extraction |
| `pkgs.cockpit-file-sharing` missing from nixpkgs | ✅ Expected — custom derivation specified |
| `services.samba.configText` / `extraConfig` removed | ✅ Resolved — use `services.samba.settings` |
| Python/awscurl runtime dependency for Samba+NFS | ✅ Not needed — S3 features out of scope |
| No blocker detected | **Phase C is feasible** |

**Phase C is unblocked and implementation can proceed.**
