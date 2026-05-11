# NAS Phase A — Package `cockpit-navigator` and Prove Cockpit Plugin Discovery on NixOS

**Project:** vexos-nix (NixOS 25.11 personal flake)
**Phase:** A of NAS feature (foundation only)
**Status:** Specification — implementation pending
**Date:** 2026-05-11
**Authoring agent:** Phase 1 Research & Specification subagent

---

## 0. Phase scope reminder (read first)

This spec covers **Phase A only**:

> Package `cockpit-navigator` (the simplest 45Drives plugin — pure static
> JS/HTML/CSS, no Python, no daemon) for NixOS, prove the Cockpit
> plugin-discovery pattern works against the immutable `/nix/store`, and
> establish the reusable foundation (overlay layout + per-plugin
> sub-option pattern) that Phases B (`cockpit-zfs`), C
> (`cockpit-file-sharing` + Samba registry mode), and D
> (`cockpit-identities` + unified `vexos.server.nas.enable`) will build on.

Out of scope for Phase A: the ZFS plugin, Samba/NFS share management,
identities, the unified `vexos.server.nas` umbrella option, and any
writable Samba state. Those are deferred to later phases and only
mentioned here in §10 (forward-compatibility).

---

## 1. Current-state analysis

### 1.1 Cockpit is already wired

[modules/server/cockpit.nix](../../../modules/server/cockpit.nix) (24 lines)
already exists and exposes:

```nix
options.vexos.server.cockpit = {
  enable = lib.mkEnableOption "Cockpit web management console";
  port   = lib.mkOption { type = lib.types.port; default = 9090; ... };
};

config = lib.mkIf cfg.enable {
  services.cockpit = {
    enable       = true;
    port         = cfg.port;
    openFirewall = true;
  };
};
```

It is registered in [modules/server/default.nix](../../../modules/server/default.nix)
under the `── Monitoring & Management` section and is therefore loaded
(but not enabled) on every server / headless-server build via the
umbrella import. It is also referenced in
[template/server-services.nix](../../../template/server-services.nix#L75)
as a commented-out opt-in line. **The "import is not enable" pattern is
already in place** — a host opts in by setting `vexos.server.cockpit.enable
= true;` in `/etc/nixos/server-services.nix`.

### 1.2 No plugin packages exist anywhere in the repo

`grep -ri 'cockpit-navigator\|cockpit-file-sharing\|cockpit-identities\|cockpit-zfs' .`
across `modules/`, `flake.nix`, and `pkgs/` returns zero matches. No
overlay supplies them. The earlier
[nas_service_spec.md](./nas_service_spec.md) (lines 410–423) **incorrectly
assumed** `pkgs.cockpit-file-sharing`, `pkgs.cockpit-navigator`,
`pkgs.cockpit-identities` exist in nixpkgs 25.11 — they do not. nixpkgs
ships only `pkgs.cockpit` (the upstream cockpit-project core), plus a
small set of *upstream* plugins (e.g. `cockpit-podman`,
`cockpit-machines` when enabled via `services.cockpit`'s downstream
options). The 45Drives plugins are **not** in nixpkgs. **This Phase A
spec corrects that error and packages cockpit-navigator from source.**

### 1.3 Plugin-discovery paths are *not* explicitly wired

The repo does **not** set `environment.etc."cockpit/...".source = ...` or
`systemd.tmpfiles.rules` for Cockpit anywhere. It relies on whatever
default discovery `services.cockpit` provides. Per upstream docs (see §2)
this is XDG_DATA_DIRS-based and does work for store packages dropped
into `environment.systemPackages` — but Phase A must *prove* this on
NixOS rather than assume it.

### 1.4 Overlay structure in `flake.nix`

The project already uses inline overlays via `nixpkgs.overlays = [...]`
attached to NixOS modules ("overlay modules"), not via a top-level
`pkgs/` directory or a `flake.nix` `overlays` output. Two examples in
[flake.nix](../../../flake.nix):

- `unstableOverlayModule` (lines ~46–55): exposes `pkgs.unstable.*`
  sourced from `nixpkgs-unstable`. Listed in every role's `baseModules`.
- `proxmoxOverlayModule` (lines ~67–69): exposes
  `inputs.proxmox-nixos.overlays.${system}`. Listed only in
  `server` / `headless-server` `baseModules`.

There is no `pkgs/default.nix` or `pkgs/<name>/default.nix` directory
yet. **Phase A introduces that convention** so future custom packages
have a home.

### 1.5 ZFS module exists and is independent

[modules/zfs-server.nix](../../../modules/zfs-server.nix) handles the ZFS
support layer. It will become relevant in Phase B (cockpit-zfs plugin)
but is **not touched** by Phase A.

### 1.6 Server-module conventions to mirror

From [modules/server/cockpit.nix](../../../modules/server/cockpit.nix),
[modules/server/adguard.nix](../../../modules/server/adguard.nix),
[modules/server/authelia.nix](../../../modules/server/authelia.nix), and
the umbrella [modules/server/default.nix](../../../modules/server/default.nix):

- Header comment: `# modules/server/<name>.nix\n# <One-line purpose>.`
- Module signature: `{ config, lib, pkgs, ... }:`
- `let cfg = config.vexos.server.<name>; in`
- Options under `vexos.server.<name>.<...>` (no other top-level option
  prefix is used for server services)
- `enable = lib.mkEnableOption "human-readable name";`
- Body wrapped in `config = lib.mkIf cfg.enable { ... };` — this is the
  **option-driven** mkIf pattern, which the project rules explicitly
  permit (the rule against `lib.mkIf` only forbids **role-driven** gates
  inside shared modules).
- Firewall ports declared explicitly (`networking.firewall.allowedTCPPorts`)
  even when `services.<x>.openFirewall = true` is also set, where the
  service has additional ports.
- Default off; opt-in lives in `/etc/nixos/server-services.nix` (see
  template).

### 1.7 Preflight expectations

[scripts/preflight.sh](../../../scripts/preflight.sh) runs:

1. `nix flake check`
2. Dry-build of all 30 variants
3. `hardware-configuration.nix` not tracked
4. `system.stateVersion` present in all 5 `configuration-*.nix`
5. `flake.lock` committed and pinned
6. Nix formatting
7. Secret scan

A new derivation must therefore **build** under `nix flake check` and
all dry-builds for `vexos-server-*` and `vexos-headless-server-*` must
succeed. Per `/memories/repo/preflight-line-endings.md`, any new shell
fragment must be LF-only (the `.gitattributes` rule covers this; no new
shell scripts are introduced by Phase A).

---

## 2. The plugin-discovery problem and chosen solution

### 2.1 The problem

Cockpit's package loader (cockpit-bridge / cockpit-ws) locates plugins
via the **XDG Base Directory Specification** — specifically, it searches
`$XDG_DATA_DIRS/cockpit/<package>/manifest.json` and falls back to a
hard-coded list. Per upstream
[`doc/guide/pages/packages.adoc`](https://github.com/cockpit-project/cockpit/blob/main/doc/guide/pages/packages.adoc)
the search order is:

1. `~/.local/share/cockpit` (per-user, uncached — dev only)
2. `/etc/cockpit` (admin overrides)
3. Each `$XDG_DATA_DIRS` entry, suffixed with `/cockpit`
4. Built-in fallback list: `/usr/local/share/cockpit`, `/usr/share/cockpit`

On a traditional FHS distro that means dropping files into
`/usr/share/cockpit/<name>/`. **On NixOS those FHS paths do not exist**
for store-installed packages. However, NixOS does set XDG_DATA_DIRS to
include `/run/current-system/sw/share` and the per-user
`/etc/profiles/per-user/<u>/share` profile paths (see
[NixOS manual — XDG Base Directories](https://nixos.org/manual/nixos/stable/#sec-xdg-base-directories)
and [nixpkgs `nixos/modules/config/system-environment.nix`](https://github.com/NixOS/nixpkgs/blob/nixos-25.11/nixos/modules/config/system-environment.nix)).
Any package added to `environment.systemPackages` whose `$out` contains
`share/cockpit/<name>/manifest.json` therefore ends up at
`/run/current-system/sw/share/cockpit/<name>/manifest.json`, which is
discoverable by Cockpit through XDG_DATA_DIRS — **no symlinking
required**.

### 2.2 Candidate solutions evaluated

| # | Candidate                                                                                          | Pros                                                                                                          | Cons                                                                                                                                                                                                | Verdict        |
| - | -------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------- |
| 1 | `environment.systemPackages = [ pkgs.vexos.cockpit-navigator ];` (pure XDG_DATA_DIRS)              | Fully declarative; idiomatic NixOS; participates in GC; no tmpfiles; no /etc churn; survives stateless tmpfs. | Relies on `services.cockpit` (cockpit-ws systemd unit) inheriting the system XDG_DATA_DIRS. NixOS module already does (verified — see §2.4).                                                         | **CHOSEN**     |
| 2 | `environment.etc."cockpit/navigator".source = "${pkg}/share/cockpit/navigator";`                   | Explicit, visible at `/etc/cockpit/navigator`.                                                                | `/etc/cockpit` is an *override* path in the upstream search order, intended for admin patches, not whole packages. Mixing override and package semantics invites confusion in Phases C/D.           | Reject         |
| 3 | `systemd.tmpfiles.rules = [ "L+ /var/lib/cockpit/plugins/navigator - - - - ${pkg}/share/cockpit/navigator" ];` | Works.                                                                                                        | Imperative; creates state under `/var/lib`; breaks impermanence (stateless role); `/var/lib/cockpit/plugins` is not in cockpit-ws's default search path on modern Cockpit (≥ 270) — would also need an XDG_DATA_DIRS extension. | Reject         |
| 4 | Wrapper derivation merging `pkgs.cockpit` + plugins into one `share/cockpit/` tree, then set `services.cockpit.package = wrapper;` | Single import path.                                                                                           | NixOS `services.cockpit` does not expose a `package` option in 25.11 (it is hard-coded); would require module override. Re-derives all of Cockpit on every plugin change, blowing the build cache.  | Reject         |

### 2.3 Chosen solution: pure XDG_DATA_DIRS via systemPackages

The Phase A module simply does:

```nix
environment.systemPackages = [ pkgs.vexos.cockpit-navigator ];
```

…inside a `lib.mkIf cfg.navigator.enable` block. The derivation
produces `$out/share/cockpit/navigator/{manifest.json,index.html,...}`.
NixOS exposes that under `/run/current-system/sw/share/cockpit/navigator/`,
which Cockpit resolves through its XDG_DATA_DIRS scan. The cockpit-ws
unit shipped by `services.cockpit` runs with the system's standard
environment (it does not strip XDG_DATA_DIRS).

**Permissions:** the store path is 0555-readable; cockpit-ws runs as
its own dedicated user (`cockpit-ws`) and only needs read access. No
ownership change required.

**SELinux/AppArmor:** NixOS does not ship either by default; the
upstream Cockpit SELinux policy is therefore moot. No policy work is
needed.

**Writability:** Phase A's plugin is purely static. Future Phases C/D
will need a writable `/etc/cockpit/cockpit.conf` plus writable
`/etc/samba/smb.conf` — those are out of scope here but flagged in §9.

### 2.4 Verification points the implementer must confirm

The Implementation subagent **must** confirm before declaring done:

1. `nixos-rebuild dry-build .#vexos-server-vm` evaluates and the closure
   contains `…cockpit-navigator-<ver>/share/cockpit/navigator/manifest.json`.
2. After a real `switch` (manual smoke test), the file
   `/run/current-system/sw/share/cockpit/navigator/manifest.json` exists
   and resolves via `readlink -f` to the store path.
3. `systemctl show cockpit.service -p Environment` shows an
   `XDG_DATA_DIRS` entry containing `/run/current-system/sw/share` (or
   the cockpit-ws unit inherits the system-wide one set by NixOS in
   `/etc/profile`/`/etc/set-environment`). If for any reason the unit
   *does not* inherit it, the fallback is to add it explicitly:

   ```nix
   systemd.services.cockpit.environment.XDG_DATA_DIRS =
     lib.mkForce "/run/current-system/sw/share";
   ```

   Implementer adds this **only if** verification step (3) fails.

4. Browser smoke test: `https://<host>:9090` → log in → "Navigator"
   appears in the left nav and lists `/`.

---

## 3. The `cockpit-navigator` derivation

### 3.1 Source

- Upstream repo: <https://github.com/45Drives/cockpit-navigator>
- License: **LGPL-3.0-only** (verified from upstream `LICENSE` file)
- Pin: latest stable tag at implementation time. As of spec authoring
  (May 2026) the latest tag is **`v0.5.10`**. The Implementation
  subagent **MUST** re-verify the latest tag from
  `https://github.com/45Drives/cockpit-navigator/releases` before
  pinning, and update `version` and the `hash` accordingly.

### 3.2 Build characteristics (from upstream Makefile)

cockpit-navigator's upstream build is a thin Makefile that:

- Has **no compilation step** (the published releases ship the bundled
  JS already; the `dist/navigator/` directory in the source tree is
  the artefact).
- The `Makefile` `install` target copies `dist/navigator/*` to
  `$(DESTDIR)/usr/share/cockpit/navigator/`.
- Has **no Python, no Node.js runtime, no systemd unit**.

Therefore the Nix derivation needs **no `nativeBuildInputs`** beyond
what `stdenv` already provides, **no `configurePhase`**, and a trivial
custom `installPhase`.

### 3.3 Derivation file

Path: `pkgs/cockpit-navigator/default.nix`

```nix
# pkgs/cockpit-navigator/default.nix
# 45Drives Cockpit Navigator — file-browser plugin for the Cockpit
# web admin UI. Static JS/HTML/CSS only; no daemon, no compilation.
# Drops files into $out/share/cockpit/navigator so Cockpit's
# XDG_DATA_DIRS scan finds them when this package is in
# environment.systemPackages.
{ lib, stdenvNoCC, fetchFromGitHub }:

stdenvNoCC.mkDerivation rec {
  pname   = "cockpit-navigator";
  version = "0.5.10";  # ← Implementer MUST re-verify latest tag at impl time

  src = fetchFromGitHub {
    owner = "45Drives";
    repo  = "cockpit-navigator";
    rev   = "v${version}";
    # ↓ Implementer fills in via: nix-prefetch-github 45Drives cockpit-navigator --rev v<ver>
    hash  = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };

  dontConfigure = true;
  dontBuild     = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/share/cockpit/navigator"
    cp -r dist/navigator/. "$out/share/cockpit/navigator/"
    runHook postInstall
  '';

  meta = with lib; {
    description = "File browser plugin for the Cockpit web admin UI (45Drives)";
    homepage    = "https://github.com/45Drives/cockpit-navigator";
    license     = licenses.lgpl3Only;
    platforms   = platforms.linux;
    maintainers = [];  # Personal flake — no nixpkgs maintainer entry.
  };
}
```

**Notes for the Implementer:**

- Use `stdenvNoCC` (no C compiler needed) to keep the closure small and
  avoid unnecessary rebuilds when the toolchain bumps.
- If the chosen upstream tag does **not** ship a pre-built
  `dist/navigator/` (older tags built it on-demand), fall back to:
  ```nix
  nativeBuildInputs = [ gnumake ];
  buildPhase = "make dist";
  installPhase = ''
    mkdir -p "$out/share/cockpit/navigator"
    cp -r dist/navigator/. "$out/share/cockpit/navigator/"
  '';
  ```
  Verify by inspecting the chosen tag's tree on github.com before
  committing.
- If `manifest.json` lives at the repo root rather than under
  `dist/navigator/`, adjust the install path accordingly. Inspect the
  pinned tag and document the actual layout in a one-line comment.

### 3.4 Layout of `$out`

```
$out/
└── share/
    └── cockpit/
        └── navigator/
            ├── manifest.json
            ├── index.html
            ├── navigator.js          (bundled)
            ├── navigator.css
            └── …
```

This is precisely the path Cockpit expects when scanning XDG_DATA_DIRS.

---

## 4. Overlay & exposure

### 4.1 Per-package file

Path: `pkgs/cockpit-navigator/default.nix` — see §3.3.

### 4.2 Overlay aggregator

Path: `pkgs/default.nix`

```nix
# pkgs/default.nix
# vexos-nix custom package overlay.
# All custom packages are exposed under the `vexos` namespace
# (pkgs.vexos.<name>) to avoid future collisions with upstream nixpkgs.
# Wired into every nixosConfiguration via the `customPkgsOverlayModule`
# helper in flake.nix.
final: prev: {
  vexos = (prev.vexos or {}) // {
    cockpit-navigator = final.callPackage ./cockpit-navigator { };
  };
}
```

The `(prev.vexos or {}) //` form is mandatory: it preserves any
previously-defined `vexos.*` attributes (none today, but Phases B/C/D
will add `vexos.cockpit-zfs`, `vexos.cockpit-file-sharing`, etc., and
they may be added by other overlay modules in the future).

### 4.3 Wiring into `flake.nix`

Add a new top-level let-binding next to `unstableOverlayModule` and
`proxmoxOverlayModule`:

```nix
# Custom in-tree packages — exposes pkgs.vexos.* via pkgs/default.nix.
# Applied to every role so any host can opt in to vexos.cockpit-navigator,
# vexos.cockpit-zfs (Phase B), etc., simply by enabling the matching
# vexos.server.cockpit.<plugin>.enable option.
customPkgsOverlayModule = {
  nixpkgs.overlays = [ (import ./pkgs) ];
};
```

Then add `customPkgsOverlayModule` to **every** role's `baseModules` in
the `roles` table (desktop, htpc, stateless, server, headless-server).
While Phase A only consumes the overlay on server/headless-server, the
overlay itself is harmless on display roles and is wired universally
for forward-consistency with Phases B/C/D and any future custom
packages.

Also add `customPkgsOverlayModule`'s overlay to the `mkBaseModule` body
(the `nixpkgs.overlays = [ ... ]` literal currently lists only the
unstable overlay) so the `nixosModules.*Base` exports consumed by
`/etc/nixos/flake.nix` thin wrappers stay in sync — this matches the
existing "no drift between mkHost and mkBaseModule" comment in
`flake.nix`.

The exact diff locations are:

- After the `proxmoxOverlayModule = { … };` block (≈ line 70).
- Inside the `roles = { … };` table — append `customPkgsOverlayModule`
  to each role's `baseModules` list.
- Inside `mkBaseModule`'s `nixpkgs.overlays = [ … ]` literal — append
  `(import ./pkgs)` after the unstable overlay.

The Implementation subagent must read `flake.nix` end-to-end before
editing to confirm line numbers (they will have shifted since this
spec was written).

---

## 5. The Cockpit + Navigator NixOS module

### 5.1 File choice — extend, do not split

Per the Option B architecture rule:

> A `configuration-*.nix` expresses its role **entirely through its
> import list** — if a file is imported, all its content applies
> unconditionally. Existing `lib.mkIf` guards in shared modules are
> tech debt to be eliminated.

However, the rule also clarifies that **option-driven** `lib.mkIf` is
the standard pattern (every existing service module under
`modules/server/` uses `lib.mkIf cfg.enable`). The navigator sub-option
is gated on `cfg.navigator.enable`, an *option*, not a role. **It is
therefore correct to extend the existing
[modules/server/cockpit.nix](../../../modules/server/cockpit.nix)
in place** rather than create a new `modules/server/cockpit-navigator.nix`.

Reasons to keep them in one file:

- Only one Cockpit instance can run per host, so the navigator option
  is conceptually nested under `vexos.server.cockpit`. Splitting would
  require the new file to reference the parent's `cfg.enable`, creating
  an evaluation ordering coupling that is awkward in Nix.
- Phases B/C/D add three more plugins. Each will be a sibling
  sub-option under `vexos.server.cockpit.<plugin>` and likely a small
  config block. Keeping them co-located in `cockpit.nix` keeps the
  surface area easy to audit.
- The umbrella import in `modules/server/default.nix` already imports
  `cockpit.nix`; no registration churn.

### 5.2 Updated module body

Path: `modules/server/cockpit.nix` (replaces existing content)

```nix
# modules/server/cockpit.nix
# Cockpit — web-based Linux server management UI, plus optional
# 45Drives plugin sub-options.
#
# Plugin discovery: Cockpit scans XDG_DATA_DIRS for share/cockpit/<name>/
# manifest.json. NixOS exposes environment.systemPackages contents
# under /run/current-system/sw/share, which is on the system XDG_DATA_DIRS,
# so adding pkgs.vexos.cockpit-navigator to systemPackages is sufficient
# — no /etc symlink, no tmpfiles. See:
#   .github/docs/subagent_docs/nas_phase_a_cockpit_navigator_spec.md
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.cockpit;
in
{
  options.vexos.server.cockpit = {
    enable = lib.mkEnableOption "Cockpit web management console";

    port = lib.mkOption {
      type        = lib.types.port;
      default     = 9090;
      description = "Port for the Cockpit web interface.";
    };

    navigator.enable = lib.mkOption {
      type        = lib.types.bool;
      default     = cfg.enable;
      description = ''
        Install the 45Drives cockpit-navigator file-browser plugin.
        Defaults to the value of vexos.server.cockpit.enable so that
        enabling Cockpit also installs Navigator (the simplest plugin)
        — set to false to opt out, or to true on its own to stage the
        package without enabling Cockpit (no effect at runtime).
      '';
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      services.cockpit = {
        enable       = true;
        port         = cfg.port;
        openFirewall = true;
      };
    })

    (lib.mkIf (cfg.enable && cfg.navigator.enable) {
      environment.systemPackages = [ pkgs.vexos.cockpit-navigator ];
    })
  ];
}
```

### 5.3 What the module does **not** do

- **No firewall rules beyond what `services.cockpit.openFirewall = true`
  already opens** (TCP 9090). Navigator does not introduce a new port.
- **No new system user.** `services.cockpit` already provisions
  `cockpit-ws` via the upstream NixOS module.
- **No `systemd.services.cockpit` overrides** unless §2.4 verification
  step (3) fails on the live host. If it does, add the
  `XDG_DATA_DIRS = lib.mkForce "/run/current-system/sw/share";`
  override inside the second `mkIf` and document the reason in a
  comment.
- **No `network-online.target` dependency** beyond what cockpit's
  upstream unit declares.
- **No `lib.mkIf` guard on a role.** The two `mkIf`s gate on
  options (`cfg.enable`, `cfg.navigator.enable`), which is the
  permitted pattern.

### 5.4 Registration

`modules/server/cockpit.nix` is **already** imported by
[modules/server/default.nix](../../../modules/server/default.nix#L48).
**No change to `default.nix` is required.** The configuration-server
and configuration-headless-server roles already pull the umbrella in
via their existing imports.

### 5.5 Opt-in template update

Update [template/server-services.nix](../../../template/server-services.nix#L75)'s
existing commented Cockpit line so a host operator can toggle Navigator
explicitly. Change:

```nix
# vexos.server.cockpit.enable = false;                # Port 9090
```

to:

```nix
# vexos.server.cockpit.enable = false;                # Port 9090
# vexos.server.cockpit.navigator.enable = true;       # 45Drives file browser plugin (Phase A)
```

Both stay commented (defaults to off via `enable = false`); the second
line is informational so an operator knows the option exists. No host
files in `hosts/` are modified by Phase A.

---

## 6. Testing & validation plan

### 6.1 Static / build-time

Run from repo root in WSL or on the NixOS host:

1. `nix flake check`
   — must pass; verifies overlay imports cleanly, derivation evaluates,
   manifest is well-formed Nix.
2. `sudo nixos-rebuild dry-build --flake .#vexos-server-amd`
   — must succeed; the closure must contain
   `…cockpit-navigator-<ver>/share/cockpit/navigator/manifest.json`.
3. `sudo nixos-rebuild dry-build --flake .#vexos-server-vm`
   — must succeed.
4. `sudo nixos-rebuild dry-build --flake .#vexos-headless-server-amd`
   — must succeed (headless servers also import the server umbrella).
5. `sudo nixos-rebuild dry-build --flake .#vexos-server-nvidia`
   — must succeed (sanity check that the universal overlay does not
   collide with NVIDIA stack).
6. `bash scripts/preflight.sh` — must pass all 7 stages.

The dry-builds in (2)–(5) cover one variant per relevant role per the
project rule "at minimum, dry-build one variant per role to catch
role-specific regressions."

### 6.2 Functional smoke test (manual, post-`switch`)

After deploying with `sudo nixos-rebuild switch --flake .#vexos-server-amd`
on a real host that has set `vexos.server.cockpit.enable = true;` in
`/etc/nixos/server-services.nix`:

1. `systemctl is-active cockpit.socket` → `active`.
2. `ls -l /run/current-system/sw/share/cockpit/navigator/manifest.json`
   → resolves to a `/nix/store/…cockpit-navigator-<ver>/…` path.
3. `readlink -f /run/current-system/sw/share/cockpit/navigator/manifest.json`
   → confirms the store-path target.
4. `cat /run/current-system/sw/share/cockpit/navigator/manifest.json`
   → valid JSON containing a `requires.cockpit` (or `require.cockpit`)
   field. Note the value — flag in §9 if it exceeds nixpkgs 25.11's
   Cockpit version.
5. Browse to `https://<host>:9090`, accept self-signed cert, log in
   with the `nimda` user.
6. Confirm a "Navigator" entry appears in the left navigation.
7. Open Navigator; confirm it lists the contents of `/`.

### 6.3 Acceptance criteria

Phase A is **complete** when:

- ✅ All 6 build-time checks in §6.1 pass.
- ✅ All 7 functional checks in §6.2 pass on at least one
  `vexos-server-*` host.
- ✅ The repo contains the four new/modified files listed in §7.
- ✅ `flake.lock` is unchanged (no new flake inputs introduced).
- ✅ `system.stateVersion` unchanged.
- ✅ `hardware-configuration.nix` not committed.

---

## 7. Implementation steps (ordered, file-by-file)

The Implementation subagent must perform these steps in order. Steps
that mutate the working tree are tagged **[edit]**.

1. **[read]** Read [flake.nix](../../../flake.nix) end-to-end and locate
   the `proxmoxOverlayModule` definition and the `roles` table.
2. **[read]** Read upstream
   `https://github.com/45Drives/cockpit-navigator/releases` and pick
   the latest stable tag. Run
   `nix-prefetch-github 45Drives cockpit-navigator --rev v<ver>`
   (or `nix flake prefetch github:45Drives/cockpit-navigator/v<ver>`)
   to obtain the SRI hash.
3. **[read]** Inspect the chosen tag's source tree
   (`https://github.com/45Drives/cockpit-navigator/tree/v<ver>`) to
   confirm whether `dist/navigator/manifest.json` ships pre-built. If
   not, prepare the `make dist` fallback noted in §3.3.
4. **[edit]** Create `pkgs/cockpit-navigator/default.nix` with the
   content from §3.3, substituting the real `version` and `hash`.
5. **[edit]** Create `pkgs/default.nix` with the content from §4.2.
6. **[edit]** Edit `flake.nix`:
   a. Add the `customPkgsOverlayModule` let-binding from §4.3 after
      `proxmoxOverlayModule`.
   b. Append `customPkgsOverlayModule` to **each** of the five roles'
      `baseModules` lists in the `roles` table.
   c. Append `(import ./pkgs)` to the `nixpkgs.overlays = [ ... ]`
      literal inside `mkBaseModule`.
7. **[edit]** Replace `modules/server/cockpit.nix` body with the
   §5.2 content.
8. **[edit]** Update the commented Cockpit lines in
   `template/server-services.nix` per §5.5.
9. **[verify]** Run `nix flake check`. Fix any evaluation errors
   surfaced by the new overlay before proceeding.
10. **[verify]** Run the four dry-builds listed in §6.1 (2)–(5). All
    must succeed.
11. **[verify]** Run `bash scripts/preflight.sh` and confirm all 7
    stages pass.
12. **[done]** Report modified file paths to the orchestrator. Manual
    smoke test (§6.2) is the human's responsibility post-deploy and is
    NOT a Phase A blocker for orchestrator approval — but the
    Implementer must call it out in the handoff summary.

---

## 8. Dependencies

### 8.1 Nixpkgs / NixOS

| Dependency                          | Source                                          | Notes                                                                                                                                  |
| ----------------------------------- | ----------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| `pkgs.cockpit`                      | nixpkgs 25.11 (already pinned via `flake.nix`)  | Provides cockpit-ws + bridge.                                                                                                          |
| `services.cockpit`                  | nixpkgs NixOS module                            | Already in use — no new option surface required.                                                                                       |
| `pkgs.stdenvNoCC` / `fetchFromGitHub` / `pkgs.callPackage` | nixpkgs                          | Standard derivation helpers.                                                                                                           |
| NixOS XDG_DATA_DIRS default         | nixpkgs `nixos/modules/config/system-environment.nix` | Sets `/run/current-system/sw/share` on XDG_DATA_DIRS for system services (verified in upstream module; see References §11).            |

### 8.2 Upstream (Context7-verified)

| Dependency                       | Version verified via                                                                | Verified API in use                                                                                                                                                                                              |
| -------------------------------- | ----------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Cockpit packages / manifest.json | Context7 `/cockpit-project/cockpit` (`doc/guide/pages/packages.adoc`)               | XDG_DATA_DIRS-based discovery; `share/cockpit/<package>/manifest.json` layout; `requires.cockpit` (modern) and legacy `require.cockpit` keys both observed in upstream docs.                                     |
| cockpit-ws environment           | Context7 `/cockpit-project/cockpit` (`doc/man/pages/cockpit-ws.8.adoc`)             | Confirms cockpit-ws honours `XDG_DATA_DIRS` for static files.                                                                                                                                                    |
| 45Drives `cockpit-navigator`     | Upstream README + Makefile (`https://github.com/45Drives/cockpit-navigator`) — Context7 has no entry for 45Drives, so upstream-direct citations used (see §11). | Static-asset Makefile installing into `/usr/share/cockpit/navigator`; LGPL-3.0; no daemon, no python, no node runtime requirement. |

### 8.3 New flake inputs

**None.** Phase A introduces zero new flake inputs. `flake.lock` does
not change. This avoids the entire "should this follow nixpkgs?"
discussion that the project's input-management rules call out.

---

## 9. Risks and mitigations

| Risk                                                                                                                                        | Likelihood | Severity | Mitigation                                                                                                                                                                                                                                                                                              |
| ------------------------------------------------------------------------------------------------------------------------------------------- | ---------- | -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| nixpkgs 25.11 ships `pkgs.cockpit` at a Cockpit version older than `manifest.json`'s `requires.cockpit` value.                              | Low        | Med      | Implementer notes the manifest's required version during §6.2 step 4. If too old, pin a newer cockpit-navigator tag, or override `services.cockpit.package = pkgs.unstable.cockpit;` (the unstable overlay is already wired in every role).                                                              |
| cockpit-ws systemd unit on NixOS does not inherit the system XDG_DATA_DIRS, so `/run/current-system/sw/share/cockpit/navigator` is invisible. | Low        | High     | Verification step §2.4 (3) catches this. Mitigation prepared in §2.4: add `systemd.services.cockpit.environment.XDG_DATA_DIRS = lib.mkForce "/run/current-system/sw/share";` inside the same mkIf block.                                                                                                |
| Upstream tag layout differs (no pre-built `dist/navigator/`).                                                                              | Low        | Low      | Fallback `buildPhase` documented in §3.3.                                                                                                                                                                                                                                                                |
| `fetchFromGitHub` hash drift if the implementer guesses the hash.                                                                          | Low        | Low      | Implementation step §7 (2) explicitly mandates `nix-prefetch-github` to obtain the SRI hash. Reproducibility is then guaranteed by the lockless source pin.                                                                                                                                              |
| Future Phases B/C will need a writable `/etc/samba/smb.conf` and `/etc/cockpit/cockpit.conf`.                                              | High       | N/A here | **Out of scope for Phase A** but flagged: the chosen pure-systemPackages discovery mechanism does not preclude later adding `environment.etc."cockpit/cockpit.conf".text = …` for runtime config. Phase C will need Samba registry mode (`include = registry`) — already analysed in `nas_service_spec.md`. |
| Plugin breaks on a Cockpit major bump (e.g. UI API change in Cockpit 320+).                                                                | Med (over time) | Med  | Pin to a known-good cockpit-navigator tag; spec re-evaluation on every Cockpit major bump. Failure mode is "Navigator missing from sidebar" — does not break Cockpit itself or any service.                                                                                                              |
| Overlay name collision: future nixpkgs adds a top-level `pkgs.cockpit-navigator`.                                                          | Low        | Low      | Already mitigated by the `pkgs.vexos.cockpit-navigator` namespace.                                                                                                                                                                                                                                       |
| `customPkgsOverlayModule` applied to display roles increases evaluation cost.                                                              | Very low   | Negligible | The overlay is a single attribute set merge — nix lazy evaluation means cockpit-navigator is only evaluated when actually referenced.                                                                                                                                                                    |

---

## 10. Forward-compatibility (Phases B / C / D)

The Phase A structure is designed so later phases require **only
additions**, not refactors:

- **`pkgs/cockpit-zfs/default.nix`** (Phase B) → registered in
  `pkgs/default.nix` as `vexos.cockpit-zfs = final.callPackage ./cockpit-zfs { };`.
  Same overlay; no `flake.nix` edits.
- **`pkgs/cockpit-file-sharing/default.nix`** (Phase C) and
  **`pkgs/cockpit-identities/default.nix`** (Phase D) → likewise.
- The `modules/server/cockpit.nix` option tree generalizes cleanly:
  - `vexos.server.cockpit.zfs.enable` → adds `pkgs.vexos.cockpit-zfs`
    (Phase B).
  - `vexos.server.cockpit.fileSharing.enable` → adds
    `pkgs.vexos.cockpit-file-sharing` plus the writable
    `/etc/samba/smb.conf` + Samba registry wiring planned in
    [nas_service_spec.md](./nas_service_spec.md) (Phase C).
  - `vexos.server.cockpit.identities.enable` → adds
    `pkgs.vexos.cockpit-identities` (Phase D).
- The unified `vexos.server.nas.enable` umbrella (Phase D) becomes a
  trivial `config = { vexos.server.cockpit.enable = lib.mkDefault true;
  vexos.server.cockpit.fileSharing.enable = lib.mkDefault true; … };`
  module — no changes required to Phase A's plumbing.
- Each plugin's `lib.mkIf cfg.<plugin>.enable` block independently
  injects its package into `environment.systemPackages`. The
  `lib.mkMerge` pattern in §5.2 is what makes that scale: every new
  plugin is one extra `mkIf` element.

The `pkgs.vexos.*` namespace is the canonical home for any future
in-tree custom package, not just Cockpit plugins.

---

## 11. References

All URLs are upstream / canonical sources. Context7 was consulted for
Cockpit (library id `/cockpit-project/cockpit`); 45Drives is not in
Context7 so direct upstream sources are cited.

1. **Cockpit upstream — Package layout & manifest.json**
   <https://github.com/cockpit-project/cockpit/blob/main/doc/guide/pages/packages.adoc>
   (verified via Context7 `/cockpit-project/cockpit`, May 2026)
2. **Cockpit upstream — `cockpit-ws(8)` man page** (XDG_DATA_DIRS support)
   <https://github.com/cockpit-project/cockpit/blob/main/doc/man/pages/cockpit-ws.8.adoc>
   (verified via Context7 `/cockpit-project/cockpit`)
3. **45Drives `cockpit-navigator` upstream repo** (Makefile, releases, LICENSE)
   <https://github.com/45Drives/cockpit-navigator>
4. **45Drives `cockpit-navigator` releases page** (tag pinning source)
   <https://github.com/45Drives/cockpit-navigator/releases>
5. **NixOS Manual — XDG Base Directories** (`/run/current-system/sw/share` on XDG_DATA_DIRS)
   <https://nixos.org/manual/nixos/stable/#sec-xdg-base-directories>
6. **nixpkgs `nixos/modules/config/system-environment.nix`** (XDG_DATA_DIRS default value)
   <https://github.com/NixOS/nixpkgs/blob/nixos-25.11/nixos/modules/config/system-environment.nix>
7. **nixpkgs `services.cockpit` NixOS module** (current option surface in 25.11)
   <https://github.com/NixOS/nixpkgs/blob/nixos-25.11/nixos/modules/services/web-apps/cockpit.nix>
8. **Cockpit upstream — Proxying / WebService configuration** (relevant for future Caddy/Authelia integration noted in §10)
   <https://github.com/cockpit-project/cockpit/wiki/Proxying-Cockpit-over-NGINX>
   (verified via Context7 `/cockpit-project/cockpit`)
9. **In-repo prior NAS spec** (corrected by §1.2 of this document)
   [.github/docs/subagent_docs/nas_service_spec.md](./nas_service_spec.md)
10. **In-repo orchestrator workflow & Option B rules**
    [.github/copilot-instructions.md](../../copilot-instructions.md)
