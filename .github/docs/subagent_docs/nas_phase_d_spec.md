# NAS Phase D — `cockpit-identities` Plugin + `vexos.server.nas.enable` Umbrella

**Project:** vexos-nix (NixOS 25.11 personal flake, `nixpkgs` pinned to
`github:NixOS/nixpkgs/nixos-25.11` rev `0c88e1f2bdb93d5999019e99cb0e61e1fe2af4c5`)
**Phase:** D of the NAS feature
**Status:** Specification — implementation pending
**Date:** 2026-05-11
**Authoring agent:** Phase 1 Research & Specification subagent

---

## 0. Phase scope reminder (read first)

This spec covers **Phase D only** — two deliverables:

**D1 — cockpit-identities plugin**
Add the 45Drives Cockpit Identities plugin as a new
`vexos.server.cockpit.identities.enable` sub-option in
`modules/server/cockpit.nix`. The plugin provides a GUI for user/group
management (Linux users, Samba passwords, groups, password resets, SSH
key management, login history) — essential for managing NAS share
permissions without SSH.

**D2 — `vexos.server.nas.enable` umbrella**
A single boolean in a new file `modules/server/nas.nix` that enables the
full NAS stack (Cockpit + navigator + file-sharing + identities) via
`lib.mkDefault`. ZFS remains opt-in and is NOT included.

Out of scope: ZFS plugin (deferred since Phase B), iSCSI, S3, Samba AD DC,
WSDD/Avahi advertisement, Python venv S3 features.

---

## 1. Availability Check — cockpit-identities in nixpkgs

### 1.1 Search results

| Source | Result |
|---|---|
| `https://search.nixos.org/packages?channel=25.05&query=cockpit-identities` | **"No packages found"** (channel redirected to 25.11, still no result) |
| `https://search.nixos.org/packages?channel=25.11&query=cockpit-identities` | **"No packages found"** |
| GitHub code search `repo:NixOS/nixpkgs cockpit-identities` | **0 code results, 0 commits, 0 issues, 0 PRs** (requires login for code results, but issues/PRs/commits are all 0) |
| Path `pkgs/tools/admin/cockpit` at pinned rev | **404 — path does not exist** at this commit |

**Conclusion: `pkgs.cockpit-identities` does NOT exist in nixpkgs at the
pinned rev `0c88e1f2bdb93d5999019e99cb0e61e1fe2af4c5`, nor in 25.11.
Custom packaging is required.**

### 1.2 Upstream release assets (45Drives/cockpit-identities)

Latest stable release: **v0.1.12** (May 11, 2023)
Repository: `https://github.com/45Drives/cockpit-identities`

| Asset | Size | Notes |
|---|---|---|
| `cockpit-identities-0.1.12-1.el8.noarch.rpm` | 4.03 MB | RHEL/CentOS 8 |
| `cockpit-identities_0.1.12-1focal_all.deb` | 3.86 MB | Ubuntu 20.04 Focal, arch:all |
| `cockpit-identities_0.1.12_generic.tar.gz` | 5.58 MB | Pre-built generic archive |
| `cockpit-identities_0.1.12_generic.zip` | 5.58 MB | Pre-built generic archive |
| Source code (.zip / .tar.gz) | — | Vue.js source, requires Yarn build |

**Key findings:**
- No Debian Bookworm `.deb` exists (unlike `cockpit-file-sharing` which had
  one). Only a Focal (Ubuntu 20.04) `.deb` is available.
- The Focal `.deb` is `arch:all` (pure static JS/CSS/HTML assets — no native
  code). This means the OS version of the `.deb` is irrelevant for extraction;
  `dpkg-deb -x` only extracts file contents, ignoring Debian metadata and
  package dependency declarations.
- A `generic.tar.gz` is also available and contains pre-built `identities/dist/`
  assets.
- The source tree uses a Vue.js + Vite + Yarn build chain; sandbox builds are
  infeasible (same pattern that blocked `cockpit-zfs` in Phase B).

### 1.3 Install path

From `Makefile` (verified at v0.1.12):
```makefile
plugin-install-% : INSTALL_PREFIX?=/usr/share/cockpit
# install step: cp -af identities/dist/* $(DESTDIR)/usr/share/cockpit/identities/
```

Inside the Focal `.deb`, the plugin lands at: `usr/share/cockpit/identities/`

This matches the pattern used by `cockpit-navigator` (`usr/share/cockpit/navigator/`)
and `cockpit-file-sharing` (`usr/share/cockpit/file-sharing/`).

---

## 2. Derivation Design — D1 (cockpit-identities packaging)

**Chosen route:** `.deb` extraction via `fetchurl` + `dpkg-deb -x`
— identical to the Phase C pattern for `cockpit-file-sharing`.

**Rationale:**
- Proven pattern: Phase C was reviewed and approved using this exact approach.
- The Focal `.deb` is `arch:all` (pure static assets); the OS version of the
  source `.deb` does not matter because we only use `dpkg-deb -x` to unpack
  file contents — no `dpkg`, `apt`, or Debian dependency resolution runs.
- The generic tarball route would also work but requires extracting from a
  nested `identities/dist/` path inside the archive, introducing more fragile
  path logic. The `.deb` route is already validated and simpler.
- Source build route is **infeasible** in Nix sandbox (Yarn Berry + network
  workspace dependencies — same reason Phase B was deferred).

### 2.1 New file: `pkgs/cockpit-identities/default.nix`

```nix
# pkgs/cockpit-identities/default.nix
# 45Drives Cockpit Identities — user and group management plugin for
# the Cockpit web admin UI. Ships as pure static JS/HTML/CSS built by
# upstream CI; we extract the pre-built assets from the official Focal
# release package rather than attempting a Yarn Berry + Vite monorepo
# build (infeasible in the Nix sandbox — same reason cockpit-zfs was
# deferred in Phase B; see nas_phase_b_cockpit_zfs_spec.md).
#
# Note: upstream only publishes a Focal (Ubuntu 20.04) .deb — no Bookworm
# variant. Because the package is arch:all (pure static assets) and we
# only use dpkg-deb -x to extract file contents, the host OS of the .deb
# is irrelevant for our purposes.
#
# Installed to $out/share/cockpit/identities/ so Cockpit's XDG_DATA_DIRS
# scan discovers the plugin's manifest.json automatically (same pattern as
# cockpit-navigator and cockpit-file-sharing).
{ lib, stdenvNoCC, fetchurl, dpkg }:

stdenvNoCC.mkDerivation rec {
  pname = "cockpit-identities";
  version = "0.1.12";
  release = "1";

  src = fetchurl {
    url = "https://github.com/45Drives/cockpit-identities/releases/download/v${version}/cockpit-identities_${version}-${release}focal_all.deb";
    hash = "sha256-PLACEHOLDER=";  # Phase 2: replace with actual hash (see §7 testing plan)
  };

  nativeBuildInputs = [ dpkg ];

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    dpkg-deb -x "$src" extracted
    mkdir -p "$out/share/cockpit"
    cp -r extracted/usr/share/cockpit/identities "$out/share/cockpit/"
    runHook postInstall
  '';

  meta = with lib; {
    description = "User and group management plugin for the Cockpit web admin UI (45Drives)";
    homepage = "https://github.com/45Drives/cockpit-identities";
    license = licenses.gpl3Only;
    platforms = platforms.linux;
    maintainers = [ ];
  };
}
```

### 2.2 Update: `pkgs/default.nix`

Add `cockpit-identities` to the `vexos` namespace, following the existing
pattern for `cockpit-navigator` and `cockpit-file-sharing`:

```nix
final: prev: {
  vexos = (prev.vexos or { }) // {
    cockpit-navigator    = final.callPackage ./cockpit-navigator { };
    cockpit-file-sharing = final.callPackage ./cockpit-file-sharing { };
    cockpit-identities   = final.callPackage ./cockpit-identities { };  # Phase D
  };
}
```

### 2.3 Hash acquisition (for Phase 2 implementor)

Run on the Linux host (WSL or NixOS directly):
```bash
nix-prefetch-url --type sha256 \
  'https://github.com/45Drives/cockpit-identities/releases/download/v0.1.12/cockpit-identities_0.1.12-1focal_all.deb'
```
Convert the resulting base32 hash to SRI format and replace the placeholder:
```bash
# If nix-prefetch-url returns a base32 hash, convert it:
nix hash to-sri --type sha256 <base32-hash-here>
# or use nix store prefetch-file directly:
nix store prefetch-file --hash-type sha256 \
  'https://github.com/45Drives/cockpit-identities/releases/download/v0.1.12/cockpit-identities_0.1.12-1focal_all.deb'
```

**CRITICAL:** All new `.nix` files must use **LF line endings** (not CRLF).
Per `/memories/repo/preflight-line-endings.md`: CRLF causes bash parse failures
in WSL. Use `sed -i 's/\r$//' file.nix` on WSL if editing on Windows.

---

## 3. Module Option Design — cockpit-identities sub-option

### 3.1 Changes to `modules/server/cockpit.nix`

Add a fourth sub-option `identities.enable` to the existing
`options.vexos.server.cockpit` attribute set, following the exact same
pattern as `navigator.enable` and `fileSharing.enable`.

**Option declaration** (insert after `fileSharing.enable` block, before the
closing `};` of the `options` set):

```nix
    identities.enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable;
      description = ''
        Install the 45Drives cockpit-identities plugin (user and group
        management GUI — Linux users, Samba passwords, groups, SSH keys,
        login history). Defaults to the value of
        vexos.server.cockpit.enable so that enabling Cockpit also installs
        Identities — set to false to opt out, or to true on its own to
        stage the package without enabling Cockpit (no effect at runtime).
      '';
    };
```

**Config fragment** (add as a fifth `lib.mkMerge` entry after the
`fileSharing` fragment):

```nix
    # ── Identities plugin ─────────────────────────────────────────────────
    (lib.mkIf (cfg.enable && cfg.identities.enable) {
      environment.systemPackages = [ pkgs.vexos.cockpit-identities ];
    })
```

**Design rationale:**
- The identities plugin is a pure static-asset Cockpit plugin — no daemons,
  no system service configuration, no firewall rules required. The only
  action needed is making `$out/share/cockpit/identities/manifest.json`
  visible to Cockpit via `environment.pathsToLink = ["/share/cockpit"]`
  (already set by the NixOS `services.cockpit` module at the pinned rev).
- Runtime dependencies (`samba`, `openssh`, `useradd`, `passwd`) are already
  present on a standard NixOS server system.
- No assertion is needed (unlike `fileSharing.enable` which requires
  `cockpit.enable`) — `identities.enable = true` without `cockpit.enable`
  just installs the package with no runtime effect, same as `navigator.enable`.
- Option B compliance: no `lib.mkIf` role guard — this is a universal fragment
  applicable to any role that imports `cockpit.nix`.

---

## 4. Umbrella Option Design — D2 (`vexos.server.nas.enable`)

### 4.1 New file: `modules/server/nas.nix`

```nix
# modules/server/nas.nix
# Umbrella option for the full NAS stack.
#
# Setting `vexos.server.nas.enable = true` is the "just make it a NAS"
# shortcut. It enables Cockpit plus all four 45Drives management plugins:
#   • cockpit-navigator   — file browser
#   • cockpit-file-sharing — Samba + NFS share management
#   • cockpit-identities  — user/group/password management
#
# Each sub-option is set via lib.mkDefault, so the operator can still
# override individual sub-options without having to touch nas.enable:
#
#   vexos.server.nas.enable = true;
#   vexos.server.cockpit.navigator.enable = false;  # this wins — lib.mkDefault loses
#
# cockpit-zfs is intentionally excluded: it requires a ZFS pool to already
# be configured on the host and has its own default auto-enable logic.
# When cockpit-zfs becomes packageable (upstream nixpkgs or a self-contained
# lockfile), adding it here is a one-line addition to this file.
{ config, lib, ... }:
let
  cfg = config.vexos.server.nas;
in
{
  options.vexos.server.nas = {
    enable = lib.mkEnableOption "full NAS stack (Cockpit web UI + navigator + file-sharing + identities plugins)";
  };

  config = lib.mkIf cfg.enable {
    vexos.server.cockpit.enable                = lib.mkDefault true;
    vexos.server.cockpit.navigator.enable      = lib.mkDefault true;
    vexos.server.cockpit.fileSharing.enable    = lib.mkDefault true;
    vexos.server.cockpit.identities.enable     = lib.mkDefault true;
  };
}
```

### 4.2 Import location

`modules/server/default.nix` imports all optional server service modules.
The NAS umbrella (`nas.nix`) must be imported there, after `cockpit.nix`
(to ensure `vexos.server.cockpit.*` options are declared before `nas.nix`
references them — Nix module evaluation is lazy but it's cleaner to list
imports in dependency order).

**Edit to `modules/server/default.nix`** — add `./nas.nix` immediately after
`./cockpit.nix` in the imports list:

```nix
    # ── Monitoring & Management ──────────────────────────────────────────────
    ./cockpit.nix
    ./nas.nix          # Phase D: NAS stack umbrella (cockpit + plugins)
    ./uptime-kuma.nix
```

This is the correct location because:
- `modules/server/default.nix` is the single authoritative import list for
  all server modules; both `configuration-server.nix` and
  `configuration-headless-server.nix` import it.
- Adding `nas.nix` here makes the option available on all server and
  headless-server configurations without touching either role config file.

---

## 5. Template Update — `template/server-services.nix`

Add a prominent commented-out `vexos.server.nas.enable = true;` line at the
top of the "Monitoring & Management" section, above the individual Cockpit
sub-option lines:

**Edit `template/server-services.nix`** — replace the existing monitoring
section header block with:

```nix
  # ── Monitoring & Management ──────────────────────────────────────────────
  # vexos.server.nas.enable = true;                     # ONE-SHOT: enables full NAS stack
  #                                                       # (Cockpit + navigator + file-sharing + identities)
  #                                                       # Individual sub-options below can still override it
  # vexos.server.cockpit.enable = false;                # Port 9090
  # vexos.server.cockpit.navigator.enable = true;       # 45Drives file browser plugin
  # vexos.server.cockpit.fileSharing.enable = true;     # 45Drives Samba + NFS share manager (requires cockpit.enable = true)
  # vexos.server.cockpit.identities.enable = true;      # 45Drives user/group management plugin
```

---

## 6. `lib.mkDefault` vs `lib.mkForce` Analysis

### 6.1 NixOS option priority table

| Expression | `mkOverride` priority | Meaning |
|---|---|---|
| Option `default =` value | 1500 | Lowest — always overridden |
| `lib.mkDefault value` | 1000 | Weaker than bare assignments |
| Bare assignment `opt = value;` | 100 | Normal user config priority |
| `lib.mkForce value` | 50 | Highest — overrides everything |

Source: NixOS manual §"Setting Priorities":
> "By default, option definitions have priority 100 and option defaults have
> priority 1500. `mkForce` is equal to `mkOverride 50`, and `mkDefault` is
> equal to `mkOverride 1000`."

### 6.2 Why `lib.mkDefault` is correct for the umbrella

The umbrella sets sub-options at priority **1000**. A bare operator assignment
in `server-services.nix` has priority **100** (lower number = higher priority).
Therefore:

```nix
# In nas.nix (priority 1000 — mkDefault):
vexos.server.cockpit.navigator.enable = lib.mkDefault true;

# In operator's server-services.nix (priority 100 — bare assignment, wins):
vexos.server.cockpit.navigator.enable = false;  # ← this wins — 100 < 1000
```

This is exactly the desired behavior: `nas.enable = true` provides a
convenient default, but individual sub-options remain freely overridable
without needing `lib.mkForce`.

Using `lib.mkForce` (priority 50) would be wrong — it would prevent the
operator from disabling individual sub-options at normal priority.

Using bare assignment (priority 100) would cause a definition conflict when
the operator sets the same option, since the module system would see two
definitions at the same priority for a `bool` type (which cannot be merged).

`lib.mkDefault` (priority 1000) is the canonical pattern for "module sets a
sensible default, user can override" and is already used by dozens of NixOS
modules for this purpose.

---

## 7. Testing Plan

### 7.1 Phase 2 hash acquisition (MUST do before building)

```bash
# On Linux/WSL host:
wsl -- bash -lc "nix-prefetch-url --type sha256 \
  'https://github.com/45Drives/cockpit-identities/releases/download/v0.1.12/cockpit-identities_0.1.12-1focal_all.deb'"
```

Place the resulting SRI hash (format: `sha256-...=`) into
`pkgs/cockpit-identities/default.nix`.

### 7.2 Package evaluation check (WSL)

```bash
wsl -- bash -lc "cd /mnt/c/Projects/vexos-nix && \
  nix-build --no-out-link -E \
  '(import <nixpkgs> { overlays = [ (import ./pkgs) ]; }).vexos.cockpit-identities' \
  2>&1 | tail -n 30"
```

Expected: successful build, `result/share/cockpit/identities/manifest.json`
exists in the output.

### 7.3 Flake check (Linux host only — not on WSL/Windows)

```bash
nix flake check
```

Must pass with no evaluation errors.

### 7.4 Dry-build variants

```bash
# Confirm server and headless-server variants evaluate correctly:
sudo nixos-rebuild dry-build --flake .#vexos-server-amd
sudo nixos-rebuild dry-build --flake .#vexos-headless-server-amd
```

### 7.5 Module option evaluation smoke test

After dry-build succeeds, confirm umbrella option wiring:

```bash
# Check identities option is recognized:
nix eval .#nixosConfigurations.vexos-server-amd.config.vexos.server.cockpit.identities.enable

# Check nas option is recognized (should evaluate without error):
nix eval .#nixosConfigurations.vexos-server-amd.config.vexos.server.nas.enable
```

### 7.6 Manual smoke test (on actual server hardware)

1. Set `vexos.server.nas.enable = true;` in `/etc/nixos/server-services.nix`
2. Run `just rebuild` or `sudo nixos-rebuild switch --flake .#vexos-server-amd`
3. Open Cockpit at `https://<server>:9090`
4. Confirm all four plugins appear in the left-nav:
   - **Files** (cockpit-navigator)
   - **File Sharing** (cockpit-file-sharing)
   - **Identities** (cockpit-identities)
5. In Identities: verify user list loads, can reset a password, can view/add
   groups.
6. Set `vexos.server.cockpit.navigator.enable = false;` alongside
   `vexos.server.nas.enable = true;` and rebuild — confirm Files tab
   disappears.

---

## 8. Risks and Mitigations

### 8.1 cockpit-identities .deb internal path

**Risk:** The internal layout of `cockpit-identities_0.1.12-1focal_all.deb`
differs from what the Makefile implies (e.g., files at `usr/share/cockpit/`
but not under `identities/`).

**Mitigation:** Before implementing, inspect the `.deb` content in WSL:
```bash
wsl -- bash -lc "
  curl -L -o /tmp/ci.deb \
    'https://github.com/45Drives/cockpit-identities/releases/download/v0.1.12/cockpit-identities_0.1.12-1focal_all.deb'
  dpkg-deb -x /tmp/ci.deb /tmp/ci-extracted
  find /tmp/ci-extracted/usr/share/cockpit -type f | head -20"
```

If the path is different, adjust the `cp -r` in `installPhase` accordingly.
Expected path: `extracted/usr/share/cockpit/identities/`.

### 8.2 Option priority conflicts

**Risk:** Operator sets both `nas.enable = true` and a sub-option to `false`
— does the override work?

**Mitigation:** Confirmed by analysis in §6 above. `lib.mkDefault` (priority
1000) always loses to a bare assignment (priority 100). No risk.

### 8.3 Import ordering — circular option references

**Risk:** `nas.nix` sets `vexos.server.cockpit.*` options. If `nas.nix` is
evaluated before `cockpit.nix` declares those options, evaluation fails.

**Mitigation:** In the NixOS module system, option declarations and definitions
are fully separated phases. All `options` across all imported modules are
collected first, then `config` blocks are evaluated. Import order in `default.nix`
does not affect option declaration visibility. No ordering constraint exists.
Placing `nas.nix` immediately after `cockpit.nix` in the import list is
purely cosmetic (human readability) — it is not technically required.

### 8.4 cockpit-identities may be stale / unmaintained

**Risk:** Last release was May 2023 (v0.1.12). The plugin uses Cockpit APIs
that may have changed.

**Mitigation:** The Cockpit plugin protocol (XDG_DATA_DIRS, `manifest.json`,
static JS) is stable across Cockpit versions. The plugin was working with
Cockpit 300+ series as of 2023. The identities UI (Vue.js + cockpit.js) uses
the stable D-Bus bridge API. Functional regression is unlikely. If a specific
Cockpit version breaks it, the operator can set
`vexos.server.cockpit.identities.enable = false;` to opt out.

### 8.5 CRLF line endings

**Risk:** Creating `.nix` files on Windows produces CRLF, causing `bash`
parse failures in WSL and Nix evaluation errors.

**Mitigation:** Per `/memories/repo/preflight-line-endings.md`, all new files
must use LF. Phase 2 implementor must strip CRLF before committing:
```bash
wsl -- bash -lc "sed -i 's/\r$//' \
  /mnt/c/Projects/vexos-nix/pkgs/cockpit-identities/default.nix \
  /mnt/c/Projects/vexos-nix/modules/server/nas.nix"
```
The preflight script (`scripts/preflight.sh`) is the final gate.

---

## 9. Forward-Compatibility Note — Adding cockpit-zfs to the NAS Umbrella

When `cockpit-zfs` eventually becomes packageable (either upstream ships it
in nixpkgs, or 45Drives fixes the Yarn Berry workspace dependency lockfile
issue that blocked Phase B), adding it to the NAS stack requires exactly
**one line** in `modules/server/nas.nix`:

```nix
  config = lib.mkIf cfg.enable {
    vexos.server.cockpit.enable                = lib.mkDefault true;
    vexos.server.cockpit.navigator.enable      = lib.mkDefault true;
    vexos.server.cockpit.fileSharing.enable    = lib.mkDefault true;
    vexos.server.cockpit.identities.enable     = lib.mkDefault true;
    vexos.server.cockpit.zfs.enable            = lib.mkDefault true;  # add this line
  };
```

No other files need to change. This is the advantage of the umbrella pattern:
it is open for extension without modification of existing declarations.

---

## 10. Sources Cited

1. **45Drives/cockpit-identities GitHub repository** (v0.1.12, May 2023)
   `https://github.com/45Drives/cockpit-identities/tree/v0.1.12`
   — Verified repo structure, Makefile install path (`/usr/share/cockpit/identities/`),
   plugin language (Vue 93.1%), license (GPL-3.0).

2. **45Drives/cockpit-identities releases page**
   `https://github.com/45Drives/cockpit-identities/releases/tag/v0.1.12`
   — Confirmed available release assets: Focal `.deb`, el8 `.rpm`,
   `generic.tar.gz`, `generic.zip`. No Bookworm `.deb` exists.

3. **NixOS packages search (25.11)**
   `https://search.nixos.org/packages?channel=25.05&query=cockpit-identities`
   — Confirmed: "No packages found" for cockpit-identities on 25.05/25.11.

4. **NixOS Manual — Option Definitions: Setting Priorities**
   `https://nixos.org/manual/nixos/stable/#sec-option-definitions-setting-priorities`
   — Confirmed priority values: `lib.mkDefault` = `mkOverride 1000` (priority 1000),
   bare assignments = priority 100, `lib.mkForce` = `mkOverride 50`.

5. **45Drives/cockpit-identities Makefile** (v0.1.12)
   `https://github.com/45Drives/cockpit-identities/blob/v0.1.12/Makefile`
   — Confirmed install path: `plugin-install-%: INSTALL_PREFIX?=/usr/share/cockpit`.
   Confirmed generic package includes `dist/` subdirectory from `identities/`.

6. **nas_phase_c_cockpit_file_sharing_spec.md** (internal precedent)
   `c:\Projects\vexos-nix\.github\docs\subagent_docs\nas_phase_c_cockpit_file_sharing_spec.md`
   — Established `.deb` extraction pattern (`fetchurl` + `dpkg-deb -x`) as the
   proven approach for Yarn Berry plugins. Confirmed `environment.systemPackages`
   + `environment.pathsToLink = ["/share/cockpit"]` discovery mechanism.

7. **nas_phase_c_cockpit_file_sharing_review_final.md** (internal precedent)
   `c:\Projects\vexos-nix\.github\docs\subagent_docs\nas_phase_c_cockpit_file_sharing_review_final.md`
   — Phase C was reviewed and APPROVED with the `.deb` pattern; confirms this
   approach is production-ready for vexos-nix.

8. **pkgs/cockpit-file-sharing/default.nix** (internal precedent code)
   `c:\Projects\vexos-nix\pkgs\cockpit-file-sharing\default.nix`
   — Reference implementation for the `dpkg-deb -x` derivation pattern.
   `cockpit-identities` derivation mirrors this exactly, differing only in
   pname, version, release, URL (focal vs bookworm), and install subdirectory.

---

## 11. Implementation Checklist for Phase 2

Phase 2 must complete all of the following, in order:

### Files to create
- [ ] `pkgs/cockpit-identities/default.nix` — derivation (LF line endings)
- [ ] `modules/server/nas.nix` — umbrella module (LF line endings)

### Files to modify
- [ ] `pkgs/default.nix` — add `cockpit-identities = final.callPackage ./cockpit-identities { };`
- [ ] `modules/server/cockpit.nix` — add `identities.enable` option + config fragment
- [ ] `modules/server/default.nix` — add `./nas.nix` import after `./cockpit.nix`
- [ ] `template/server-services.nix` — add `nas.enable` commented line + `identities.enable` line

### Pre-commit steps
1. Acquire `.deb` SHA256 hash and insert into derivation (replaces `PLACEHOLDER`)
2. Strip CRLF from all new `.nix` files
3. Run `nix flake check` on Linux host
4. Run `sudo nixos-rebuild dry-build --flake .#vexos-server-amd`

### Constraints (must not violate)
- Do NOT change `system.stateVersion`
- Do NOT add `hardware-configuration.nix` to this repo
- Do NOT add new flake inputs
- Do NOT add `lib.mkIf` role guards inside shared module files (Option B)
- All new `.nix` files must use LF line endings
