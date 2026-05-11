# NAS Phase B — Package `cockpit-zfs` Ourselves and Wire It Through the Existing Cockpit Module

**Project:** vexos-nix (NixOS personal flake, `nixpkgs` pinned to
`github:NixOS/nixpkgs/nixos-25.11` rev
`0c88e1f2bdb93d5999019e99cb0e61e1fe2af4c5`)
**Phase:** B of the NAS feature (ZFS plugin)
**Status:** Specification — implementation pending
**Date:** 2026-05-11
**Authoring agent:** Phase 1 Research & Specification subagent
**Revision:** 2 — supersedes the prior Phase B spec, which was wrong about
nixpkgs already shipping `cockpit-zfs` and about `services.cockpit.plugins`
existing.

---

## 0. Phase scope reminder (read first)

This spec covers **Phase B only**:

> Enable the 45Drives `cockpit-zfs` plugin (and the `py-libzfs` Python
> bindings it shells out to) on the `server` and `headless-server` roles
> via a new sub-option `vexos.server.cockpit.zfs.enable` on the existing
> Cockpit module — without breaking any other role.

Out of scope for Phase B: `cockpit-file-sharing` (Phase C),
`cockpit-identities` (Phase D), the unified `vexos.server.nas.enable`
umbrella option (Phase D), Samba registry-mode share management,
SELinux contexts, the optional `cockpit-alerts` companion plugin
referenced by `cockpit-zfs`'s `manifest.json` (deferred — see §10),
and activation of `system_files/*` shipped with cockpit-zfs (D-Bus
configs, ZED scripts, storage-alert systemd units — also §10).

---

## 1. Headline finding (READ THIS FIRST — supersedes Revision 1)

The prior revision of this spec asserted three things that are **false**
against the project's pinned nixpkgs rev
(`0c88e1f2bdb93d5999019e99cb0e61e1fe2af4c5`). Verified directly against
that rev's source tree:

| Prior Rev. 1 claim | Reality at the pinned rev | Source |
|---|---|---|
| `pkgs.cockpit-zfs` is already in nixpkgs | **Does NOT exist.** Returns "MISSING" on `nix eval`. | User-verified `nix eval` against the pin |
| `pkgs.python312Packages.py-libzfs` (TS-25.10.1) is already in nixpkgs | A `py-libzfs` **does** exist (`pkgs.python3Packages.py-libzfs`, version `24.04.0`, truenas fork) — but **on `python3Packages`, not `python312Packages`** | User-verified `nix eval` against the pin |
| `services.cockpit.plugins` is the idiomatic NixOS option for cockpit plugins | **Does NOT exist.** The `services.cockpit` option set at this rev is exactly: `enable`, `package`, `allowed-origins`, `settings`, `showBanner`, `port`, `openFirewall`. There is **no `plugins` attribute.** | [`nixos/modules/services/monitoring/cockpit.nix`](https://github.com/NixOS/nixpkgs/blob/0c88e1f2bdb93d5999019e99cb0e61e1fe2af4c5/nixos/modules/services/monitoring/cockpit.nix) |

This forces three structural corrections to Phase B:

1. **We must package `cockpit-zfs` ourselves** under
   `pkgs/cockpit-zfs/default.nix`, exposed as
   `pkgs.vexos.cockpit-zfs` via the existing `pkgs/default.nix`
   overlay (the same overlay that already exposes
   `pkgs.vexos.cockpit-navigator`).
2. **We reuse `pkgs.python3Packages.py-libzfs` from nixpkgs** rather
   than packaging `45Drives/python3-libzfs` from source — the truenas
   fork is upstream-of, structurally identical to (same C-extension
   module name `libzfs`, same setup, same nvpair/zfs_core link), and
   already built against the same `pkgs.zfs` that
   `boot.zfs.package` resolves to in this nixpkgs eval. The original
   ABI-coupling concern is therefore solved by reusing the nixpkgs
   build of `py-libzfs`. **No second derivation under
   `pkgs/python3-libzfs/` is needed.**
3. **Plugin discovery uses the Phase A pattern**
   (`environment.systemPackages` → `environment.pathsToLink = [
   "/share/cockpit" ]` → XDG_DATA_DIRS scan), because
   `services.cockpit.plugins` does not exist at this rev. This also
   reverses the prior revision's claim that the Phase A pattern is
   "wrong" for cockpit-zfs — see §3 for why it is in fact sufficient.

### What Phase B actually does, in one paragraph

Add a `pkgs/cockpit-zfs/default.nix` derivation that fetches
`45Drives/cockpit-zfs` v1.2.26, runs the upstream yarn-based frontend
build, installs the `zfs/dist/*` tree to `$out/share/cockpit/zfs/`,
and registers it under `pkgs.vexos.cockpit-zfs` via
`pkgs/default.nix`. Then add a `vexos.server.cockpit.zfs.enable`
sub-option to `modules/server/cockpit.nix` (default
`cfg.enable && config.boot.zfs.enabled`) that, when true, appends both
`pkgs.vexos.cockpit-zfs` and
`(pkgs.python3.withPackages (ps: [ ps.py-libzfs ]))` to
`environment.systemPackages`, plus a fail-fast assertion if the user
flips the option on without ZFS active. No new flake inputs. No
changes to `modules/zfs-server.nix`. No changes to `flake.nix`.

---

## 2. Current-state analysis

### 2.1 Phase A overlay scaffolding is in place and gets extended (not replaced)

[flake.nix](../../../flake.nix) defines:

```nix
customPkgsOverlayModule = {
  nixpkgs.overlays = [ (import ./pkgs) ];
};
```

…and lists it in **every** role's `baseModules` (desktop, htpc,
stateless, server, headless-server). [pkgs/default.nix](../../../pkgs/default.nix)
currently exposes the single attribute:

```nix
final: prev: {
  vexos = (prev.vexos or { }) // {
    cockpit-navigator = final.callPackage ./cockpit-navigator { };
  };
}
```

Phase B extends this attrset with one more entry
(`cockpit-zfs = final.callPackage ./cockpit-zfs { };`) — no other
overlay or flake-input change is required. The
`(prev.vexos or { }) //` form already preserves the namespace
correctly.

### 2.2 `pkgs/cockpit-navigator/default.nix` is the precedent we partially mirror

[pkgs/cockpit-navigator/default.nix](../../../pkgs/cockpit-navigator/default.nix)
uses `stdenvNoCC.mkDerivation` with `dontConfigure = true; dontBuild =
true;` because cockpit-navigator's source repo ships pre-built static
assets under `navigator/`. **`cockpit-zfs` is different**: its source
repo ships only TypeScript / Vue source under `zfs/src/`, and the
upstream `Makefile` runs `yarn install && yarn run build` to produce
`zfs/dist/`. We therefore cannot reuse the no-build pattern verbatim;
see §4 for the build-required derivation.

We do still mirror cockpit-navigator's:

- `fetchFromGitHub` source pin
- `meta` block layout
- Output-path convention: `$out/share/cockpit/<plugin>/`
- Single-attribute callPackage registration in `pkgs/default.nix`

### 2.3 The Cockpit module already uses a `lib.mkMerge` + sub-option pattern

[modules/server/cockpit.nix](../../../modules/server/cockpit.nix) (Phase
A's final shape):

```nix
options.vexos.server.cockpit = {
  enable = lib.mkEnableOption "Cockpit web management console";
  port   = lib.mkOption { type = lib.types.port; default = 9090; ... };
  navigator.enable = lib.mkOption {
    type = lib.types.bool;
    default = cfg.enable;
    ...
  };
};

config = lib.mkMerge [
  (lib.mkIf cfg.enable
    { services.cockpit = { enable = true; port = cfg.port; openFirewall = true; }; })
  (lib.mkIf (cfg.enable && cfg.navigator.enable)
    { environment.systemPackages = [ pkgs.vexos.cockpit-navigator ]; })
];
```

Phase B adds a third merge fragment, gated by a new option
`cfg.zfs.enable`, holding both an `assertions` entry and an
`environment.systemPackages` entry. **No structural deviation from
Phase A.** Both `mkIf`s gate on options, not roles — Option B
compliant.

### 2.4 The ZFS support layer is independent and stays untouched

[modules/zfs-server.nix](../../../modules/zfs-server.nix) is imported
**only** by `configuration-server.nix` and
`configuration-headless-server.nix`. It sets
`boot.supportedFilesystems = [ "zfs" ];`, `boot.zfs.forceImportRoot
= false;`, ZFS scrub/trim, and `pkgs.zfs` on
`environment.systemPackages`.

`config.boot.zfs.enabled` evaluates to **true** on the two server
roles and **false** on desktop/htpc/stateless. That is the predicate
Phase B uses for the default of the new sub-option.

### 2.5 `config.boot.zfs.enabled` is the canonical "ZFS is active" predicate (verified)

Verified directly against the pinned nixpkgs rev's
[`nixos/modules/tasks/filesystems/zfs.nix`](https://github.com/NixOS/nixpkgs/blob/0c88e1f2bdb93d5999019e99cb0e61e1fe2af4c5/nixos/modules/tasks/filesystems/zfs.nix):

```nix
inInitrd = config.boot.initrd.supportedFilesystems.zfs or false;
inSystem = config.boot.supportedFilesystems.zfs or false;
...
boot.zfs.enabled = lib.mkOption {
  readOnly    = true;
  type        = lib.types.bool;
  default     = inInitrd || inSystem;
  defaultText = lib.literalMD "`true` if ZFS filesystem support is enabled";
  description = "True if ZFS filesystem support is enabled";
};
```

Two key facts confirmed:

1. **`config.boot.zfs.enabled` IS a read-side option** (`readOnly =
   true`) — using it from another module's `config = ...` is supported
   and is the idiom used across nixpkgs (PAM, containerd, incus,
   cadvisor, kubelet).
2. The internal predicate uses
   `config.boot.supportedFilesystems.zfs or false`, which is the
   correct shape for `boot.supportedFilesystems` at this rev (see
   §2.6). We do **not** need to write that predicate by hand —
   `config.boot.zfs.enabled` already encapsulates it.

### 2.6 `boot.supportedFilesystems` is `attrsOf bool` (NOT a list) at this rev

Verified directly against the pinned rev's
[`nixos/modules/tasks/filesystems.nix`](https://github.com/NixOS/nixpkgs/blob/0c88e1f2bdb93d5999019e99cb0e61e1fe2af4c5/nixos/modules/tasks/filesystems.nix):

```nix
attrNamesToTrue = types.coercedTo (types.listOf types.str) (
  enabledList: lib.genAttrs enabledList (_attrName: true)
) (types.attrsOf types.bool);
...
boot.supportedFilesystems = mkOption {
  default = { };
  example = literalExpression ''{ btrfs = true; zfs = lib.mkForce false; }'';
  type    = attrNamesToTrue;
  ...
};
```

So **at the read site, `config.boot.supportedFilesystems` is an
attrset of bool, not a list.** The legacy
`lib.elem "zfs" config.boot.supportedFilesystems` predicate would fail
type-check. The correct hand-written predicate would be
`(config.boot.supportedFilesystems.zfs or false)` — but as noted in
§2.5 we use `config.boot.zfs.enabled` instead, which is strictly
better (it also covers the initrd-only case).

### 2.7 `services.cockpit.plugins` does NOT exist at this rev (verified)

Verified directly against the pinned rev's cockpit module at
[`nixos/modules/services/monitoring/cockpit.nix`](https://github.com/NixOS/nixpkgs/blob/0c88e1f2bdb93d5999019e99cb0e61e1fe2af4c5/nixos/modules/services/monitoring/cockpit.nix).
The full `options.services.cockpit` option set at this rev is:

| Option | Type | Default |
|---|---|---|
| `enable` | bool | false |
| `package` | package | `pkgs.cockpit` |
| `allowed-origins` | listOf str | `[ ]` |
| `settings` | iniFormat | `{ }` |
| `showBanner` | bool | true |
| `port` | port | 9090 |
| `openFirewall` | bool | false |

**There is no `plugins` option.** Plugin discovery at this rev is
entirely XDG_DATA_DIRS-based, wired by the same module via:

```nix
environment.systemPackages = [ cfg.package ];          # cockpit-bridge on PATH
environment.pathsToLink    = [ "/share/cockpit" ];     # surfaces share/cockpit subtrees
```

That is, **any package added to `environment.systemPackages` whose
`$out/share/cockpit/<name>/manifest.json` exists is auto-discovered**
by cockpit-bridge through the standard XDG_DATA_DIRS scan rooted at
`/run/current-system/sw/share`. This is exactly the Phase A pattern,
and it is the only mechanism available at this rev.

### 2.8 nixpkgs python3 / py-libzfs at this rev

User-verified facts:

- `pkgs.python3Packages.py-libzfs` exists, version **`24.04.0`**
  (truenas fork — upstream-of and structurally identical to
  `45Drives/python3-libzfs`, same `libzfs` Python-module name).
- `pkgs.cockpit` exists, version **`351`**.

Implementer note: the cockpit module at this rev does **not** expose
`cockpit.passthru.python3Packages` — that plumbing post-dates this
pin. We therefore wire `py-libzfs` through `pkgs.python3` directly,
not through `cockpit.passthru.python3Packages`. As long as `pkgs.zfs`
is the same in both `pkgs.python3Packages.py-libzfs` and
`config.boot.zfs.package`'s eval (which is true by construction —
they share the same `nixpkgs` instance), the libzfs ABI lines up.

### 2.9 Preflight expectations

[scripts/preflight.sh](../../../scripts/preflight.sh) runs `nix flake
check` plus dry-build of all 30 variants. The new derivation is a
yarn-berry frontend build — on a cold Nix store, dry-build will
download the offline yarn cache (hundreds of MB) for every variant
that pulls it in, but that download is cached by Nix and reused across
variants. Only the two server roles' twelve variants actually pull
`pkgs.vexos.cockpit-zfs` into their closure (the other eighteen
variants evaluate the option default to `false` and the package is
never instantiated). No preflight script changes are required. Per
`/memories/repo/preflight-line-endings.md`, no new shell scripts are
introduced, so LF-only enforcement is not a concern.

---

## 3. Plugin-discovery decision: stay with the Phase A pattern

### 3.1 Why `environment.systemPackages` is the right (and only) mechanism here

Two reasons, both decisive:

1. **`services.cockpit.plugins` does not exist at this rev** (§2.7).
   There is no other declarative mechanism in the cockpit NixOS module
   to add plugin packages. The XDG_DATA_DIRS pattern via
   `environment.systemPackages` is the *only* path the upstream module
   exposes.
2. **The plugin's runtime needs are met by Phase A's pattern plus a
   second `systemPackages` entry for python3+py-libzfs.**
   `cockpit-zfs`'s helper scripts invoke
   `cockpit.spawn(['/usr/bin/env', 'python3', '-c', script, …])`
   (verified against
   [`zfs/src/scripts/get-pools.py`](https://github.com/45Drives/cockpit-zfs/blob/v1.2.26/zfs/src/scripts/get-pools.py)
   and friends). This resolves through:
   - `/usr/bin/env` — provided on NixOS by the default
     `environment.usrbinenv = "${pkgs.coreutils}/bin/env";`.
   - `python3` — resolved on PATH. NixOS's cockpit-bridge inherits the
     system PATH from systemd, which includes
     `/run/current-system/sw/bin`.
   - `import libzfs` inside that python3 — works iff the `python3` on
     PATH is a `python3.withPackages (ps: [ ps.py-libzfs ])`
     wrapper (which is precisely what we install on
     `environment.systemPackages` alongside the plugin).

   No `/etc/cockpit/lib/python3.X/site-packages` injection is
   required. No `wrapProgram` overlay. No `passthru.cockpitPath`
   plumbing. The plugin's own scripts use `/usr/bin/env python3`,
   which is the cleanest possible coupling for our purposes.

### 3.2 Why the prior revision's argument was wrong for our pin

Revision 1 claimed `services.cockpit.plugins` was the *only* working
option for cockpit-zfs because the plugin needs `PYTHONPATH` wired by
the cockpit module's `depsEnv` machinery. That argument was based on a
**newer** nixpkgs cockpit module (the one on the `nixos-25.11` HEAD
that does have `services.cockpit.plugins`, `passthru.cockpitPath`, and
the `/etc/cockpit/{bin,lib,share}` symlink-merge). The project pins to
a **specific older rev** that pre-dates that rewrite. At the pinned
rev, none of that machinery exists; the discovery model is
strictly XDG_DATA_DIRS.

The runtime requirement (`import libzfs` works inside the python3
that the plugin shells out to) is met just as well — and more simply
— by putting a `python3.withPackages` wrapper on the system PATH. It
participates in the system closure, in GC, in the standard NixOS
profile, and works on the stateless role's tmpfs-rooted system without
extra wiring.

### 3.3 Alternatives evaluated

| # | Candidate | Verdict |
|---|---|---|
| 1 | `environment.systemPackages = [ pkgs.vexos.cockpit-zfs (pkgs.python3.withPackages (ps: [ ps.py-libzfs ])) ];` | **CHOSEN.** Idiomatic, identical mechanism to Phase A, works at the pinned rev, no overlay surgery, no `wrapProgram`, no `/etc/cockpit/*` writes. |
| 2 | `services.cockpit.plugins = [ pkgs.vexos.cockpit-zfs ];` | **Reject — option does not exist** at the pinned rev (§2.7). Would fail evaluation immediately. |
| 3 | Bump `nixpkgs` pin to a newer rev that has `services.cockpit.plugins` and `pkgs.cockpit-zfs` | Reject — out of Phase B scope. A nixpkgs bump touches every flake output and must be its own change. Revisit only if Phase D needs something only the new module provides. |
| 4 | Inject py-libzfs via a `wrapProgram` overlay over `pkgs.cockpit` so cockpit-bridge always has `import libzfs` available | Reject — invasive override of an upstream package, no clear benefit over the systemPackages wrapper, harder to reason about. |
| 5 | Use the **archived** `45Drives/cockpit-zfs-manager` (pure JS, no python helpers) | Reject — explicitly deprecated by 45Drives; their README says "this repo has been archived and we encourage users to check out our new cockpit-zfs module here." Last release Nov 2023, archived March 2026. Not a viable long-term target. |

### 3.4 Should Phase A's `cockpit-navigator` wiring change?

**No.** It already uses `environment.systemPackages` — Phase B uses
the exact same mechanism, so consistency is preserved by the chosen
solution. No change to the navigator block.

---

## 4. The `cockpit-zfs` derivation

### 4.1 Source

- Upstream repo: <https://github.com/45Drives/cockpit-zfs>
- License: **GPL-3.0+** (verified from upstream `manifest.json`)
- Pin: `v1.2.26` (latest stable tag at spec authoring; verified
  via the GitHub releases page — released ~2 weeks before this spec).
  The Implementation subagent **MUST** re-verify the latest stable
  (non-pre-release) tag from
  <https://github.com/45Drives/cockpit-zfs/releases> at implementation
  time and update `version` and the SRI hashes accordingly.

### 4.2 Build characteristics (verified from upstream Makefile)

cockpit-zfs's upstream
[`Makefile`](https://github.com/45Drives/cockpit-zfs/blob/v1.2.26/Makefile)
does **not** ship pre-built `dist/`. Building requires:

```make
PLUGIN_SRCS=zfs

bootstrap-yarn:
	./bootstrap.sh        # writes .yarnrc.yml

houston-common:
	$(MAKE) -C houston-common   # builds the git-submodule shared library

$(OUTPUTS): %/dist/index.html: bootstrap-yarn houston-common $$(...)
	yarn --cwd $* install
	yarn --cwd $* run build
```

…and the install target is:

```make
plugin-install-%:
	mkdir -p $(DESTDIR)$(INSTALL_PREFIX)/$*$(INSTALL_SUFFIX)
	cp -rf --no-preserve=context $*/dist/* $(DESTDIR)$(INSTALL_PREFIX)/$*$(INSTALL_SUFFIX)
# INSTALL_PREFIX = /usr/share/cockpit
```

So the produced layout we must reproduce is:

```
$out/share/cockpit/zfs/{index.html,manifest.json,assets/*,...}
```

Two complications:

1. **Git submodule `houston-common`.** `.gitmodules` references
   `houston-common/` which the Makefile builds before the plugin
   itself. `fetchFromGitHub` with `fetchSubmodules = true;` is
   required.
2. **`bootstrap.sh` writes `.yarnrc.yml`.** It must run before
   `yarn install`. We invoke `bash bootstrap.sh` explicitly in
   `preBuild`.

### 4.3 Yarn-cache pinning strategy

The Makefile uses Yarn (Berry / v3+) when `yarn` is on PATH, falling
back to npm otherwise. We pin to Yarn (Berry) because that is the
upstream-supported toolchain. Nixpkgs at this rev provides the
`yarnConfigHook` / `yarnBuildHook` / `fetchYarnDeps` triumvirate for
reproducibly fetching a Yarn Berry offline cache.

The implementer pins **two** SRI hashes:

1. `src.hash` — the `fetchFromGitHub` hash, obtained via
   `nix-prefetch-github 45Drives cockpit-zfs --rev v<ver> --fetch-submodules`.
2. `offlineCache.hash` — the `fetchYarnDeps` hash for the
   plugin-subdir `yarn.lock`. Obtained via:

   ```sh
   nix-build -E 'with import <nixpkgs> {}; fetchYarnDeps {
     yarnLock = (fetchFromGitHub {
       owner = "45Drives"; repo = "cockpit-zfs"; rev = "v1.2.26";
       fetchSubmodules = true; hash = "<src hash>";
     }) + "/zfs/yarn.lock";
     hash = lib.fakeSha256;
   }'
   ```

   The first build will fail and report the real hash, which the
   implementer pastes in. Pin the same way for `houston-common`'s
   `yarn.lock` if that submodule has its own Yarn build (verify
   during implementation by inspecting
   `houston-common/Makefile`); if it does, declare a second
   `houstonOfflineCache = fetchYarnDeps { … }` and a second yarn
   project root.

### 4.4 Derivation file

Path: `pkgs/cockpit-zfs/default.nix`

```nix
# pkgs/cockpit-zfs/default.nix
# 45Drives Cockpit ZFS — ZFS pool/dataset/snapshot management UI for the
# Cockpit web admin console. Vue/TypeScript frontend built with Yarn (Berry);
# Python helper scripts that import `libzfs` at runtime (the runtime python3
# wrapper is provided by the consuming module, not by this derivation).
#
# Build pattern: vendor the Yarn offline cache via fetchYarnDeps, run
# `bash bootstrap.sh && yarn install --immutable && yarn run build` against
# the plugin subdir, then install the produced `zfs/dist/*` to
# $out/share/cockpit/zfs/ — exactly what the upstream Makefile's
# plugin-install-% target does (with INSTALL_PREFIX=/usr/share/cockpit).
{ lib
, stdenv
, fetchFromGitHub
, fetchYarnDeps
, yarnConfigHook
, yarnBuildHook
, nodejs
, yarn-berry
, gnumake
, jq
, moreutils
, git
, cacert
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "cockpit-zfs";
  version = "1.2.26";  # ← Implementer MUST re-verify latest stable tag

  src = fetchFromGitHub {
    owner = "45Drives";
    repo  = "cockpit-zfs";
    rev   = "v${finalAttrs.version}";
    fetchSubmodules = true;     # houston-common is a git submodule
    # Implementer fills in via:
    #   nix-prefetch-github 45Drives cockpit-zfs --rev v<ver> --fetch-submodules
    hash = lib.fakeHash;
  };

  # The yarn-berry offline cache pin for the plugin's own yarn.lock.
  # If houston-common ships its own yarn.lock, add a second
  # `houstonOfflineCache = fetchYarnDeps { … }` and a second
  # yarnConfigHook invocation in preBuild.
  offlineCache = fetchYarnDeps {
    yarnLock = "${finalAttrs.src}/zfs/yarn.lock";
    hash = lib.fakeHash;
  };

  nativeBuildInputs = [
    yarnConfigHook
    yarnBuildHook
    nodejs
    yarn-berry
    gnumake
    jq
    moreutils       # bootstrap.sh uses `sponge`
    git             # houston-common's Makefile may shell out to git
    cacert          # bootstrap.sh may fetch over HTTPS
  ];

  # Yarn's project root for yarnConfigHook is the plugin subdir, not the
  # repo root.
  yarnConfigHookExtraArgs = [ ];
  yarnFlags = [ ];
  yarnBuildScript = "build";
  yarnBuildHookExtraArgs = [ "--cwd" "zfs" ];

  # bootstrap.sh writes .yarnrc.yml at the repo root, which the plugin's
  # yarn install needs. Do this *before* yarnConfigHook runs.
  postPatch = ''
    patchShebangs bootstrap.sh
    bash bootstrap.sh
  '';

  # Ensure houston-common is built first (the Makefile does this for us
  # if invoked with `make`, but we want to keep the steps explicit).
  preBuild = ''
    if [ -f houston-common/Makefile ]; then
      make -C houston-common
    fi
  '';

  # Replace the default install with the plugin-install pattern from the
  # upstream Makefile. yarnBuildHook produces zfs/dist/*; we copy that
  # tree into $out/share/cockpit/zfs/.
  installPhase = ''
    runHook preInstall
    install -d "$out/share/cockpit/zfs"
    cp -r zfs/dist/. "$out/share/cockpit/zfs/"
    runHook postInstall
  '';

  meta = with lib; {
    description = "ZFS pool/dataset/snapshot management plugin for Cockpit (45Drives)";
    homepage    = "https://github.com/45Drives/cockpit-zfs";
    license     = licenses.gpl3Plus;
    platforms   = platforms.linux;
    maintainers = [ ];   # personal flake — no nixpkgs maintainer entry
  };
})
```

**Implementer notes — read carefully before pinning hashes:**

- Some upstream tags may not have `zfs/yarn.lock` checked in if the
  CI generates it at build time. Inspect the v1.2.26 tag's tree on
  GitHub before committing to the `offlineCache` strategy. If
  `yarn.lock` is missing, fall back to checking out the
  CI-generated lockfile from a 45Drives release artefact, or pin a
  later tag that does ship `yarn.lock` (45Drives publishes 60+
  releases, several of which do).
- If `bootstrap.sh` requires network access at build time
  (e.g. it `curl`s something), the derivation will fail in the
  sandbox. Inspect `bootstrap.sh` end-to-end during implementation;
  if it does network I/O, either patch the script to use a vendored
  alternative or model that fetch as a separate `fetchurl`-type
  fixed-output derivation.
- If `houston-common` has its own `yarn.lock`, repeat the
  `fetchYarnDeps` + `yarnConfigHook` steps inside `preBuild` for
  that subtree before invoking the plugin build.
- The `yarn-berry` package name in nixpkgs is `yarn-berry`
  (`pkgs.yarn-berry`); `pkgs.yarn` is the legacy v1 client. Use the
  Berry one to match upstream's `.yarnrc.yml`.
- If at impl time a simpler nixpkgs Yarn-Berry abstraction exists in
  the pinned rev (e.g. `mkYarnPackage` / `yarn2nix`), the implementer
  may use it instead — the constraint is only that the closure
  contains `$out/share/cockpit/zfs/manifest.json` and `index.html`,
  built reproducibly without network access at build time.

### 4.5 Layout of `$out`

```
$out/
└── share/
    └── cockpit/
        └── zfs/
            ├── manifest.json
            ├── index.html
            ├── assets/         # bundled JS / CSS / images
            └── …               # whatever else `yarn build` produces under zfs/dist/
```

This is the only path Cockpit needs in order to surface "ZFS" in the
left navigation. Everything in `system_files/` (D-Bus configs,
storage-alert systemd timer, ZED scripts) is **deliberately not
installed** by Phase B — see §10.

---

## 5. Overlay aggregator

Path: `pkgs/default.nix` (modify in place — append one entry)

Final shape:

```nix
# pkgs/default.nix
# vexos-nix custom package overlay.
# All custom packages are exposed under the `vexos` namespace
# (pkgs.vexos.<name>) to avoid future collisions with upstream nixpkgs.
# Wired into every nixosConfiguration via the `customPkgsOverlayModule`
# helper in flake.nix.
final: prev: {
  vexos = (prev.vexos or { }) // {
    cockpit-navigator = final.callPackage ./cockpit-navigator { };
    cockpit-zfs       = final.callPackage ./cockpit-zfs { };
  };
}
```

`flake.nix` is **not** edited — `customPkgsOverlayModule` is already
listed in every role's `baseModules`, so the new attribute is
universally available to every host without further wiring (and lazy
evaluation keeps it out of any closure that doesn't reference it).

---

## 6. Module wiring (`modules/server/cockpit.nix`)

### 6.1 Final shape (replaces existing content)

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
# environment.pathsToLink = [ "/share/cockpit" ]. cockpit-zfs additionally
# needs python3 + py-libzfs on PATH (the plugin shells out to
# `/usr/bin/env python3 -c '...; import libzfs; ...'`); we satisfy that
# by also putting a (python3.withPackages [ py-libzfs ]) wrapper on
# systemPackages. See:
#   .github/docs/subagent_docs/nas_phase_a_cockpit_navigator_spec.md
#   .github/docs/subagent_docs/nas_phase_b_cockpit_zfs_spec.md
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

    zfs.enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable && config.boot.zfs.enabled;
      description = ''
        Install the 45Drives cockpit-zfs plugin (ZFS pool / dataset /
        snapshot management UI) and a python3 wrapper carrying the
        py-libzfs Python bindings.

        Defaults to true on roles that have BOTH Cockpit enabled AND
        ZFS active (server, headless-server). Defaults to false on
        roles without ZFS (desktop, htpc, stateless) even if Cockpit
        is enabled there, because the plugin is useless without ZFS
        and pulls in a non-trivial closure (the yarn-built frontend
        plus the python3 + py-libzfs wrapper).

        Setting this to true on a role without ZFS will fail
        evaluation with an actionable assertion message — enable ZFS
        first (import modules/zfs-server.nix or set
        boot.supportedFilesystems.zfs = true), or leave this option
        at its default.
      '';
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      services.cockpit = {
        enable = true;
        port = cfg.port;
        openFirewall = true;
      };
    })

    (lib.mkIf (cfg.enable && cfg.navigator.enable) {
      environment.systemPackages = [ pkgs.vexos.cockpit-navigator ];
    })

    (lib.mkIf cfg.zfs.enable {
      assertions = [{
        assertion = config.boot.zfs.enabled;
        message = ''
          vexos.server.cockpit.zfs.enable is true but ZFS is not
          enabled on this system (config.boot.zfs.enabled = false).

          Either:
            • Import modules/zfs-server.nix (via configuration-server.nix
              or configuration-headless-server.nix), OR
            • Set boot.supportedFilesystems = { zfs = true; }; explicitly, OR
            • Leave vexos.server.cockpit.zfs.enable at its default
              (which only auto-enables when ZFS is already active).
        '';
      }];

      # Both packages go on systemPackages:
      #  - pkgs.vexos.cockpit-zfs surfaces $out/share/cockpit/zfs/
      #    via environment.pathsToLink = [ "/share/cockpit" ] (set by
      #    services.cockpit) and the system XDG_DATA_DIRS scan.
      #  - The python3.withPackages wrapper places `python3` on PATH
      #    with `import libzfs` resolvable, which is what the plugin's
      #    `useSpawn(['/usr/bin/env','python3','-c',script,...])` calls
      #    actually need at runtime.
      environment.systemPackages = [
        pkgs.vexos.cockpit-zfs
        (pkgs.python3.withPackages (ps: [ ps.py-libzfs ]))
      ];
    })
  ];
}
```

### 6.2 What the module deliberately does NOT do

- **No `services.cockpit.plugins` reference** — the option does not
  exist at this rev (§2.7).
- **No `wrapProgram` / `cockpit.passthru.python3Packages` overlay
  surgery.** Not needed; `/usr/bin/env python3` resolves through the
  systemPackages wrapper.
- **No `/etc/cockpit/lib/python3.X/site-packages` symlinks.** Not
  needed for the same reason.
- **No firewall changes beyond what Phase A already opens (TCP
  9090).** Cockpit-zfs introduces no new ports.
- **No new system user.** Cockpit-zfs runs entirely as the
  authenticated browser user via cockpit-bridge.
- **No `systemd.packages` for cockpit-zfs's `system_files/` units.**
  Out of scope (§10).
- **No `lib.mkIf` guard on a role.** All three `mkIf`s gate on
  options. Option B compliant.

### 6.3 Registration

`modules/server/cockpit.nix` is **already** imported by
[modules/server/default.nix](../../../modules/server/default.nix).
**No change to `default.nix` is required.** Both
`configuration-server.nix` and `configuration-headless-server.nix`
already pull the umbrella.

### 6.4 Optional opt-in template update

[template/server-services.nix](../../../template/server-services.nix)
should gain one informational commented line so an operator knows the
new sub-option exists. Match the surrounding section's tone — the
existing `# vexos.server.cockpit.enable = true;` style. Suggested
addition (location TBD by implementer — adjacent to the existing
Cockpit lines):

```nix
# vexos.server.cockpit.zfs.enable = true;       # 45Drives cockpit-zfs (auto-enabled on ZFS)
```

This is **optional**; skipping it does not block Phase B acceptance.

---

## 7. Use of Context7

Per the project's Context7 policy: Context7 was queried for
Cockpit (`/cockpit-project/cockpit`) and confirmed the upstream plugin
discovery model is XDG_DATA_DIRS-based, with `share/cockpit/<plugin>/`
as the install path. Context7 has no entries for `45Drives/cockpit-zfs`
or `truenas/py-libzfs`, so direct upstream-source citations are used
for those (see References §11). Context7 has no entry for
NixOS-module-level options; the pinned-rev nixpkgs source tree itself
was used as the authoritative reference for `services.cockpit`,
`boot.supportedFilesystems`, and `boot.zfs.enabled`.

---

## 8. Implementation steps (ordered, file-by-file)

The Implementation subagent must perform these steps in order.

1. **[read]** Verify upstream:
   - Latest stable (non-pre-release) tag on
     <https://github.com/45Drives/cockpit-zfs/releases>. Confirm or
     update the `version = "1.2.26"` pin in §4.4.
   - That tag's tree contains `zfs/yarn.lock`. If absent, see
     §4.4 fallback notes.
   - That `bootstrap.sh` does not perform network I/O (read it
     end-to-end). If it does, prepare the patch noted in §4.4.
   - That `houston-common/` is the only git submodule and does not
     itself require a separate Yarn cache. If it does, declare a
     second `fetchYarnDeps` in `pkgs/cockpit-zfs/default.nix`.
2. **[verify]** Confirm `pkgs.python3Packages.py-libzfs` is available
   on the project's pinned nixpkgs:
   ```sh
   nix eval .#nixosConfigurations.vexos-headless-server-amd.pkgs.python3Packages.py-libzfs.version
   ```
   Should print `"24.04.0"` (per the user-verified facts).
3. **[edit]** Create `pkgs/cockpit-zfs/default.nix` with the §4.4
   content. Pin both hashes:
   - `src.hash`: `nix-prefetch-github 45Drives cockpit-zfs --rev v<ver> --fetch-submodules`
   - `offlineCache.hash`: see the trial-build trick in §4.3.
4. **[edit]** Append the `cockpit-zfs = final.callPackage ./cockpit-zfs { };`
   line to `pkgs/default.nix`'s `vexos` attrset, per §5.
5. **[edit]** Replace `modules/server/cockpit.nix` body with the
   §6.1 content.
6. **[edit, optional]** Add the §6.4 line to
   `template/server-services.nix`.
7. **[verify]** Run `nix flake check`. Must pass.
8. **[verify]** Run the four targeted dry-builds in §9.2. Must
   succeed.
9. **[verify]** Run `bash scripts/preflight.sh`. All seven stages
   must pass.
10. **[done]** Report modified file paths to the orchestrator. The
    manual smoke test (§9.4) is the human's responsibility post-deploy
    and is NOT a Phase B blocker for orchestrator approval — but the
    Implementer must call it out in the handoff summary.

**[do NOT]** Edit `flake.nix`. Edit `modules/zfs-server.nix`. Add a
new flake input. Touch `system.stateVersion`. Commit
`hardware-configuration.nix`. Create `pkgs/python3-libzfs/`.

---

## 9. Testing & validation plan

### 9.1 Preflight (mandatory, gates Phase 6)

```sh
bash scripts/preflight.sh
```

Runs `nix flake check` plus dry-build of all 30 variants. The
yarn-built `pkgs.vexos.cockpit-zfs` will be evaluated and its source +
offline cache fetched on a cold Nix store; this is acceptable
(`dry-build` evaluates and downloads but does not actually run the
yarn build). Only the twelve server / headless-server variants pull
the package into their closure; the other eighteen evaluate it lazily
to nothing.

### 9.2 Targeted dry-builds (developer loop)

```sh
sudo nixos-rebuild dry-build --flake .#vexos-headless-server-amd     # primary target
sudo nixos-rebuild dry-build --flake .#vexos-server-amd              # primary target
sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd             # regression check (must NOT pull cockpit-zfs)
sudo nixos-rebuild dry-build --flake .#vexos-stateless-amd           # regression check (must NOT pull cockpit-zfs)
```

The two regression checks are critical: the default chain
(`cfg.zfs.enable = cfg.enable && config.boot.zfs.enabled`) must keep
`pkgs.vexos.cockpit-zfs` and the `python3.withPackages` wrapper out of
the closure on display roles. Verify by inspecting the closure:

```sh
nix path-info --recursive .#nixosConfigurations.vexos-desktop-amd.config.system.build.toplevel \
  | grep -E 'cockpit-zfs|py-libzfs' || echo "OK: not in closure"
```

Should print `OK: not in closure`. Run the symmetric check on
`vexos-headless-server-amd` and confirm both substrings DO appear.

### 9.3 Sanity eval

```sh
nix eval .#nixosConfigurations.vexos-headless-server-amd.pkgs.vexos.cockpit-zfs.drvPath
nix eval .#nixosConfigurations.vexos-headless-server-amd.pkgs.python3Packages.py-libzfs.version
```

Both must succeed, returning a `/nix/store/*.drv` path and `"24.04.0"`
respectively.

### 9.4 Assertion fail-fast check

Temporarily set `vexos.server.cockpit.enable = true;` and
`vexos.server.cockpit.zfs.enable = true;` inside `hosts/desktop-amd.nix`
(a role without ZFS). Run
`sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd`. The build
**must** fail at evaluation with the assertion message from §6.1.
Revert the change after verification.

### 9.5 Post-`switch` smoke test (manual, on a real host)

After `sudo nixos-rebuild switch --flake .#vexos-headless-server-amd`
on a host that has set `vexos.server.cockpit.enable = true;` in
`/etc/nixos/server-services.nix`:

1. `systemctl is-active cockpit.socket` → `active`.
2. `ls -l /run/current-system/sw/share/cockpit/zfs/manifest.json`
   resolves to a `/nix/store/…cockpit-zfs-<ver>/share/cockpit/zfs/…`
   path.
3. `which python3` resolves to a store path under
   `…python3-<ver>-env/bin/python3` (the `withPackages` wrapper).
4. `python3 -c 'import libzfs; print(libzfs.__file__)'` prints a
   path under `/nix/store/.../site-packages/libzfs/`.
5. Browse to `https://<host>:9090`, log in. A "ZFS" entry appears in
   the left navigation.
6. Open the ZFS page; "Storage Pools" lists actual pools (or the
   empty-state UI on a fresh host). Listing pools confirms the
   plugin's `import libzfs` calls are succeeding through cockpit-bridge.

### 9.6 Acceptance criteria

Phase B is **complete** when:

- ✅ All 6 build-time / eval checks (§9.1–9.4) pass.
- ✅ §9.5 smoke test passes on at least one `vexos-server-*` or
  `vexos-headless-server-*` host (human-deferred — not a Phase 6
  blocker).
- ✅ The repo contains the three new/modified files listed in §12.
- ✅ `flake.lock` unchanged (no new flake inputs).
- ✅ `system.stateVersion` unchanged.
- ✅ `hardware-configuration.nix` not committed.

---

## 10. Risks and mitigations

| # | Risk | Severity | Mitigation |
|---|---|---|---|
| **A** | `cockpit-zfs` UI assumes a Cockpit version newer than the pinned `pkgs.cockpit` (`351`). The plugin's `manifest.json` may declare a `requires.cockpit` that's higher than 351. | Medium | Implementer reads `zfs/manifest.json` from the pinned tag during impl. If the required version exceeds 351, either: (a) pin an older cockpit-zfs tag whose manifest is satisfied, or (b) pin a newer cockpit via `services.cockpit.package = pkgs.unstable.cockpit;` (the unstable overlay is already wired). Document the chosen mitigation in a comment on the derivation. |
| **B** | `bootstrap.sh` does network I/O at build time → fails in the Nix sandbox. | Medium | Inspect end-to-end during impl (§8 step 1). If it does, patch the script in `postPatch` to use vendored alternatives, or pre-stage the needed file as a separate fixed-output `fetchurl`. |
| **C** | `houston-common` git submodule has its own yarn build with a separate `yarn.lock`. | Medium | Detect during impl (§8 step 1). If true, add a second `fetchYarnDeps` and a second `yarnConfigHook` invocation in `preBuild` — see §4.4. |
| **D** | Yarn-Berry version mismatch between upstream's pinned `.yarnrc.yml` and `pkgs.yarn-berry` at this rev. | Medium | If `yarn install --immutable` rejects the version, use `pkgs.yarn-berry.override { … }` to pin a matching version, or patch `.yarnrc.yml` in `postPatch`. |
| **E** | py-libzfs at version `24.04.0` (truenas) has API drift from the version `45Drives/cockpit-zfs` v1.2.26 was developed against. | Medium | Truenas `py-libzfs` is the upstream of the 45Drives fork; the C-extension API surface (pool/dataset/snapshot/property accessors) has been stable since 2020. The smoke test (§9.5 step 6) is the definitive go/no-go. If incompatibility is found, mitigations in priority order: (1) pin an older `cockpit-zfs` tag whose helper scripts match `24.04.0`'s API; (2) bump nixpkgs (out of Phase B scope); (3) package `45Drives/python3-libzfs` from source under `pkgs/python3-libzfs/` as a Phase B.1 follow-up. |
| **F** | cockpit-zfs's `manifest.json` declares `cockpit-alerts` as a runtime dependency. Without it, a notification widget may be broken (UI may show errors but core pool/dataset management should still function). | Low | Phase B does **not** package `cockpit-alerts`. Document the gap. Defer to a follow-up phase ("Phase B.1") if the smoke test reveals user-visible breakage beyond the notification UI. |
| **G** | `system_files/*` (D-Bus configs at `etc/dbus-1/system.d/`, ZED scripts at `etc/zfs/zed.d/`, storage-alert systemd timer) are NOT installed by Phase B. | Medium — feature gap, not breakage | The plugin's pool/dataset/snapshot management UI does not depend on these files. Email storage alerts and ZED-driven event reactions are the affected features. Document the gap explicitly here; defer activation to a later phase. Implementer must confirm during smoke test that the core UI works without them. |
| **H** | User explicitly enables `vexos.server.cockpit.zfs.enable` on a non-ZFS role. | Low | Assertion in §6.1 fails evaluation with a clear, actionable message. |
| **I** | Closure inflation on display roles from the universally-applied overlay. | Negligible | Overlay only registers a `callPackage` thunk; lazy evaluation means `pkgs.vexos.cockpit-zfs` is never realized unless something references it. The default chain ensures only server / headless-server variants reference it. |
| **J** | A future `nix flake update` bump of the nixpkgs pin moves to a rev that DOES ship `pkgs.cockpit-zfs` and `services.cockpit.plugins`, making this Phase B implementation redundant. | Low — desirable, not a defect | Treat as a future Phase B refactor opportunity: at that point, drop `pkgs/cockpit-zfs/`, drop the `vexos.cockpit-zfs` overlay entry, and switch the module's `lib.mkIf cfg.zfs.enable` body to `services.cockpit.plugins = [ pkgs.cockpit-zfs ];`. The option surface (`vexos.server.cockpit.zfs.enable`) and its default chain remain unchanged, so consumers are unaffected. |

---

## 11. Forward-compatibility (Phases C and D)

Phase B's structure leaves the next two phases mechanical:

### Phase C (`cockpit-file-sharing`)

- Add `pkgs/cockpit-file-sharing/default.nix` (probably another
  yarn-build derivation; verify upstream).
- Register as `pkgs.vexos.cockpit-file-sharing` in `pkgs/default.nix`.
- Add `vexos.server.cockpit.fileSharing.enable` sub-option, default
  `cfg.enable && config.services.samba.enable or false` (or similar
  predicate — TBD when Phase C is specced).
- A fourth `lib.mkMerge` fragment appends the package to
  `environment.systemPackages`. Same shape as Phase B.

### Phase D (`cockpit-identities` + unified `vexos.server.nas.enable`)

- Same shape as Phase C for the plugin itself.
- The unified `vexos.server.nas.enable` becomes a new top-level
  option (under `vexos.server.nas`, not `vexos.server.cockpit`) that
  sets the four sub-option enables under `vexos.server.cockpit.*`
  plus `services.samba.enable` and any NAS hardening needed.

No structural changes to Phase B are required. The
`lib.mkMerge` extension pattern in §6.1 scales linearly to N plugins.

### Out-of-scope items the implementer should NOT touch in Phase B

- Activating `system_files/` from cockpit-zfs (D-Bus configs,
  storage-alert systemd timer, ZED scripts).
- Packaging `cockpit-alerts`, `cockpit-file-sharing`, or
  `cockpit-identities`.
- Bumping the nixpkgs pin.
- Modifying `modules/zfs-server.nix`, `system.stateVersion`,
  `hardware-configuration.nix`, or any kernel/ZFS pinning.
- Adding new flake inputs.

---

## 12. Files the Implementation phase will create / modify

**Create:**

- `pkgs/cockpit-zfs/default.nix`

**Modify:**

- `pkgs/default.nix` — append one `cockpit-zfs = …;` entry to the
  `vexos` attrset.
- `modules/server/cockpit.nix` — replace body with the §6.1 content
  (adds `zfs.enable` sub-option, third `mkMerge` fragment, header
  comment update).

**Modify (optional):**

- `template/server-services.nix` — append one informational
  commented line (§6.4).

**Do NOT modify:**

- `flake.nix`, `flake.lock`, `modules/zfs-server.nix`, any
  `configuration-*.nix`, any `hosts/*.nix`, any `home-*.nix`,
  `scripts/preflight.sh`, `pkgs/cockpit-navigator/default.nix`.

---

## 13. References

All URLs are to the exact source tree relied upon. Verified live
against the project's pinned nixpkgs rev
(`0c88e1f2bdb93d5999019e99cb0e61e1fe2af4c5`) where applicable.

1. **nixpkgs (pinned rev) — `nixos/modules/services/monitoring/cockpit.nix`**
   — confirms `services.cockpit` option set has no `plugins`
   attribute; confirms `environment.pathsToLink = [ "/share/cockpit"
   ]` is the wiring mechanism.
   <https://github.com/NixOS/nixpkgs/blob/0c88e1f2bdb93d5999019e99cb0e61e1fe2af4c5/nixos/modules/services/monitoring/cockpit.nix>
2. **nixpkgs (pinned rev) — `nixos/modules/tasks/filesystems/zfs.nix`**
   — confirms `boot.zfs.enabled` is `readOnly = true` and defaults to
   `inInitrd || inSystem` where `inSystem =
   config.boot.supportedFilesystems.zfs or false`.
   <https://github.com/NixOS/nixpkgs/blob/0c88e1f2bdb93d5999019e99cb0e61e1fe2af4c5/nixos/modules/tasks/filesystems/zfs.nix>
3. **nixpkgs (pinned rev) — `nixos/modules/tasks/filesystems.nix`**
   — confirms `boot.supportedFilesystems` is
   `attrNamesToTrue` (a `coercedTo (listOf str) (attrsOf bool)`).
   <https://github.com/NixOS/nixpkgs/blob/0c88e1f2bdb93d5999019e99cb0e61e1fe2af4c5/nixos/modules/tasks/filesystems.nix>
4. **45Drives — `cockpit-zfs` upstream repo, README, releases**
   (latest stable tag `v1.2.26`; explicitly supersedes the archived
   `cockpit-zfs-manager`; runtime deps include `python3`,
   `python3-libzfs`, `python3-dateutil`, `sqlite3`, `jq`, `msmtp`,
   `cockpit-alerts`).
   <https://github.com/45Drives/cockpit-zfs>,
   <https://github.com/45Drives/cockpit-zfs/releases>
5. **45Drives — `cockpit-zfs` v1.2.26 `Makefile`** — confirms the
   yarn-build flow (`bootstrap.sh` → `yarn install` → `yarn run build`
   → `cp -rf zfs/dist/* /usr/share/cockpit/zfs/`); confirms the
   `houston-common` submodule build step.
   <https://github.com/45Drives/cockpit-zfs/blob/v1.2.26/Makefile>
6. **45Drives — `cockpit-zfs` v1.2.26 `manifest.json`** — confirms
   GPL-3.0+ license, version, runtime dependency list (notably
   `cockpit-alerts`, deferred per §10/G).
   <https://github.com/45Drives/cockpit-zfs/blob/v1.2.26/manifest.json>
7. **45Drives — archived `cockpit-zfs-manager`** — confirms the
   legacy plugin is deprecated and points users at `cockpit-zfs`.
   <https://github.com/45Drives/cockpit-zfs-manager>
8. **TrueNAS — `py-libzfs` upstream repo** — Python module name
   `libzfs`; the C-extension API consumed by `cockpit-zfs`'s helper
   scripts. nixpkgs's `pkgs.python3Packages.py-libzfs` packages this
   repo at version `24.04.0` (per user-verified `nix eval`).
   <https://github.com/truenas/py-libzfs>
9. **NixOS option semantics — `config.boot.zfs.enabled` usage across
   nixpkgs** (cross-references confirming this is the canonical
   "is ZFS active?" predicate; same usage pattern carried over from
   prior nixpkgs revs):
   <https://github.com/NixOS/nixpkgs/blob/0c88e1f2bdb93d5999019e99cb0e61e1fe2af4c5/nixos/modules/security/pam.nix>,
   <https://github.com/NixOS/nixpkgs/blob/0c88e1f2bdb93d5999019e99cb0e61e1fe2af4c5/nixos/modules/virtualisation/incus.nix>
10. **vexos-nix — Phase A spec** (precedent for derivation layout,
    overlay registration, sub-option pattern, and the
    `environment.systemPackages` discovery mechanism reused here):
    [`.github/docs/subagent_docs/nas_phase_a_cockpit_navigator_spec.md`](./nas_phase_a_cockpit_navigator_spec.md)
11. **vexos-nix — Option B architecture rules** (file naming, no
    role-based `lib.mkIf`, option-driven sub-modules):
    [`.github/copilot-instructions.md`](../../copilot-instructions.md)
12. **Cockpit upstream — package layout / manifest.json /
    XDG_DATA_DIRS discovery** (verified via Context7
    `/cockpit-project/cockpit`):
    <https://github.com/cockpit-project/cockpit/blob/main/doc/guide/pages/packages.adoc>
