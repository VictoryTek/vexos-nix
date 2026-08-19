# Custom Kernel Pipeline (OGC first) — Specification

**Feature:** `kernel_pipeline`
**Date:** 2026-08-19
**Status:** Draft — Phase 1 (revised after investigation gate)

A **device-agnostic, multi-kernel** build-and-serve pipeline: any host running
Harmonia can be designated a kernel builder, and any desktop can consume the
result with zero per-host configuration. OGC is the first kernel in the
registry; adding another is a directory plus one registry line.

---

## 0. Investigation Gate — RESULTS

Phase 1 was gated on two unknowns. Both are now resolved with live data, and
both came back **more favourable than assumed**.

### 0.1 Config fragments — GATE PASSED

`OpenGamingCollective/kernel-packages/config/ogc.config.{set,unset}`:

| File | Lines |
|------|-------|
| `ogc.config.set` | **149** |
| `ogc.config.unset` | **24** |

These are **not** a Fedora kernel config. They are a small, purely-additive
device-enablement delta:

- `CONFIG_NTSYNC=m` — gaming synchronisation primitive
- **ASUS laptop WMI / wireless modules, ASUS Ally HID** ← relevant to this user's hardware
- Handheld enablement: Steam Deck (USB/DWC3, audio, sensors, LEDs), Legion Go, MSI Claw, Ayaneo, OneXPlayer, GPD Win
- Framework / ChromeOS `CROS_EC` variants
- `CONFIG_ANDROID_BINDER_IPC=y` (Waydroid)
- BPF/eBPF + `sched_ext` scheduler support

The `.unset` file is 24 lines, mostly Steam Deck USB gadget/debug options.

**Consequence:** the feared Fedora entanglement does not exist. This is ~173
lines of mechanical `CONFIG_*` translation into `structuredExtraConfig`,
layering cleanly onto **nixpkgs'** base kernel config. Risk R-2 drops from High
to Low. This is the single biggest change from the pre-investigation draft.

### 0.2 The patch — GATE PASSED, and it changes the packaging approach

`OpenGamingCollective/linux` **does** publish releases with assets (the earlier
"no releases" result was the *kernel-packages* repo, not this one). Each release
carries a `monolithic.patch`, plus cryptographic signatures and public keys:

| Release | `monolithic.patch` size |
|---------|------------------------|
| `v7.2-ogc3` | 431,416 B |
| `v7.2-ogc2` | 333,397 B |
| `v7.2-rc7-ogc7` | 336,339 B |

~431 KB is a focused patch series, not a heavyweight downstream fork. Useful as
a *review artifact* (it is the readable summary of what OGC changes), but —
see §0.3 — **not** what the Nix build consumes.

### 0.3 We are not constrained to nixpkgs' kernel versions — approach confirmed

An earlier draft worried that OGC's base version (e.g. 7.2) might not match
whatever kernel nixpkgs currently ships (e.g. 7.1.8), making the patch fail to
apply. **That premise was wrong**, and it made the work look harder than it is.

Verified against `nixpkgs/pkgs/os-specific/linux/kernel/xanmod-kernels.nix`:
third-party kernels in nixpkgs define **their own version and their own source**,
fetched from the upstream project's own repo, and pass `version` /
`modDirVersion` explicitly to `buildLinux`:

```nix
src = fetchFromGitLab { owner = "xanmod"; repo = "linux"; rev = modDirVersion; inherit hash; };
buildLinux (args // rec {
  inherit version;
  pname = "linux-xanmod";
  modDirVersion = lib.versions.pad 3 "${version}-${suffix}";
```

This bypasses nixpkgs' packaged kernel versions completely.

Because **OGC's tags are already on a pre-patched tree**, the same pattern
applies directly: fetch the OGC tag, build it. There is **no patch to apply, no
base version to match, and no coordination with nixpkgs' kernel version at all.**
A `fetchFromGitHub` tarball snapshot (no git history) is on the order of a
couple hundred MB, downloaded once per kernel version, on the builder only —
entirely acceptable, and exactly what xanmod already does in nixpkgs.

---

## 1. Current State Analysis

### 1.1 Relevant existing infrastructure

| File | Role |
|------|------|
| `modules/server/harmonia.nix` | Working; `openFirewall` currently opens the port **LAN-wide**; key auto-generated per host. |
| `modules/nix.nix` | `vexos.harmonia.cacheUrl`/`publicKey` are **nullable opt-in** — the manual-paste problem. |
| `modules/network.nix:178` | `services.tailscale` enabled **unconditionally, all roles**. |
| `just setup-tailscale` (justfile:835) | Per-machine enrollment; already the established onboarding step. |
| `modules/server/joplin.nix:213` | **Pattern to copy**: `networking.firewall.interfaces.tailscale0.allowedTCPPorts`. |
| `modules/server/joplin.nix:205` | **Pattern to copy**: `systemd.timers` + `OnCalendar` + `Persistent`. |
| `.github/workflows/update-brave-origin-weekly-thursday.yml` | **Pattern to copy**: check upstream → rewrite pin → verify → commit only on success. |
| `modules/secrets-sops.nix` | sops secret + template blocks; `vexos.secrets.backend`. |
| `modules/nix.nix:137-138` | `min-free`/`max-free` auto-GC — **will delete an unpinned kernel**. |
| `pkgs/default.nix` | `pkgs.vexos.*` overlay, applied to every role. |
| `_feature_names` (justfile:948) | `gaming development print3d virtualization sunshine` |

### 1.2 Upstream OGC — verified

`OpenGamingCollective/linux` is a Linux stable fork; OGC releases are **tags on
the patched tree** plus a `monolithic.patch` release asset. Tag streams:

| Stream | Pattern | Cadence |
|--------|---------|---------|
| stable (**target**) | `v7.2-ogc3`, `v7.1.8-ogc1` | multiple/day when active |
| release candidate | `v7.2-rc7-ogc7` | multiple/day |
| LTS | `v6.18.44-lts-ogc1` | weeks–months |

Selection: newest tag matching `^v[0-9].*-ogc[0-9]+$`, **excluding** `-rc` and `-lts`.

---

## 2. Problem Definition

1. No Nix packaging for the OGC kernel exists.
2. Desktop hosts cannot build it on demand (hours per build).
3. Harmonia requires manual per-host config and has a non-portable key.
4. Harmonia's port is open LAN-wide while serving the entire host store.
5. **Any design must be device-agnostic and multi-kernel** — no host may be
   hardcoded, and adding a second kernel later must not require re-architecture.

**Success criterion:** a desktop runs `just update` and receives a pre-built
kernel as a *download*, with no host-specific configuration ever written, on any
machine present or future.

---

## 3. Architecture

```
 GitHub Actions (nightly)      builder host (nightly timer)        any desktop
 ────────────────────────      ───────────────────────────        ───────────
 for each registry kernel:
   find newest upstream tag
   prefetch patch hash
   rewrite version.json
   EVALUATE (not build)
   commit on success ──────────► git pull
                                 evaluate kernel drvPath
                                 already built? no-op
                                 nix build  (hours)
                                 nix-store --add-root   ← survives GC
                                        │
                                 Harmonia serves it ───────────► just update
                                 over tailscale0 as `cache`      substitutes
```

**Device-agnostic by construction.** No hostname appears anywhere in the
implementation. The builder is an opt-in service (`vexos.server.kernelBuilder`)
enableable on *any* host; the cache is reached by the Tailscale MagicDNS name
`cache`, which follows whichever machine currently holds it. Moving the whole
pipeline to different hardware means enabling two options there and renaming the
tailnet host — no repo edits.

**Two decisions and their rationale** (recorded, not open for input):

1. *Tag-checking runs in GitHub Actions, not on the builder.* CI needs only a
   hash prefetch plus a flake evaluation — seconds. It cannot build a kernel
   (6 h cap, ~14 GiB runner disk) and does not need to. This keeps the builder a
   pure builder with **no GitHub push credentials and no new secrets**.

2. *The builder evaluates "what does the repo currently ask for?" rather than
   tracking tags.* A kernel's store path depends on the upstream tag **and** the
   nixpkgs revision, and `update-flake-lock-daily.yml` bumps nixpkgs daily. A
   tag-tracking builder would silently miss those bumps and every desktop would
   fall back to compiling locally. Evaluating the current derivation covers both
   causes with one mechanism. This is the most load-bearing decision here.

---

## 4. Part A — Kernel registry (extensible)

### 4.1 `pkgs/kernels/default.nix` — the registry

```nix
# Adding a kernel = one directory + one line here. Nothing else changes:
# the builder, the client module, and the CI workflow all read this registry.
{ callPackage }:
{
  ogc = callPackage ./ogc { };
}
```

Surfaced through the existing overlay as `pkgs.vexos.kernels.<name>`.

### 4.2 `pkgs/kernels/ogc/version.json` — machine-written pin

```json
{
  "tag":           "v7.2-ogc3",
  "version":       "7.2",
  "modDirVersion": "7.2.0",
  "hash":          "sha256-..."
}
```

Sole coupling between builder and consumers. **Only ever written by CI.**

### 4.3 `pkgs/kernels/ogc/default.nix`

Follows the verified `xanmod-kernels.nix` pattern (§0.3) — own version, own
source, no dependence on nixpkgs' kernel version:

```nix
{ lib, buildLinux, fetchFromGitHub, linuxPackagesFor, ... } @ args:
let
  pin = lib.importJSON ./version.json;
in
linuxPackagesFor (buildLinux (args // rec {
  inherit (pin) version;
  pname         = "linux-ogc";
  modDirVersion = pin.modDirVersion;      # see R-4
  src = fetchFromGitHub {
    owner = "OpenGamingCollective";
    repo  = "linux";
    rev   = pin.tag;                      # tree is ALREADY patched
    inherit (pin) hash;
  };
  kernelPatches         = [];             # nothing to apply
  structuredExtraConfig = import ./config.nix { inherit lib; };
  extraMeta.branch      = lib.versions.majorMinor pin.version;
}))
```

### 4.4 `pkgs/kernels/ogc/config.nix`

Mechanical translation of the **173 verified lines** of `ogc.config.set` /
`ogc.config.unset` into `structuredExtraConfig` using
`lib.kernel.{yes,no,module,freeform}`, layered on nixpkgs' base config.

Deliberately **not** reproducing Fedora's full config — that path caused this
repo's previous Bazzite-kernel failure (`kernel_replace_spec.md` documents a
`makeModulesClosure allowMissing` hack needed because a Fedora-config kernel
omitted modules NixOS expected). The investigation confirms this is unnecessary:
OGC's delta is additive device enablement, base-config agnostic.

---

## 5. Part B — Harmonia: portable, zero-config, tailnet-only

| # | Change | Detail |
|---|--------|--------|
| B-1 | Firewall → tailnet only | Replace `networking.firewall.allowedTCPPorts` with `networking.firewall.interfaces.tailscale0.allowedTCPPorts`, per `joplin.nix:213`. Harmonia serves the whole store; LAN-wide is too broad. |
| B-2 | Signing key → sops | Add `harmonia-cache-priv-key` to `modules/secrets-sops.nix` (`owner=root`, `mode=0400`). Keep activation-script generation as the non-sops fallback, mirroring `attic.nix`. Makes the key **portable across hosts** — required for B-3. |
| B-3 | Baked-in client defaults | `vexos.harmonia.cacheUrl` default `http://cache:5000`; `publicKey` default = committed public half. Both non-secret. Every host inherits them; still overridable. **This is what eliminates the manual paste.** |

**Two Tailscale admin-console actions** (not repo changes): enable MagicDNS, and
name the builder host `cache`. No reverse proxy, no Caddy, no DNS server —
Tailscale is the stable routing layer and MagicDNS names are private to the
tailnet by construction.

---

## 6. Part C — CI: `.github/workflows/update-kernels-nightly.yml`

Modeled on `update-brave-origin-weekly-thursday.yml`. Matrix over the registry so
new kernels are picked up automatically.

1. Trigger: `schedule` (nightly, offset from the 04:00/05:00 jobs) + `workflow_dispatch`.
2. Query `api.github.com/repos/OpenGamingCollective/linux/releases`.
3. Select newest stable tag (`-ogc<N>`, excluding `-rc`/`-lts`); `sort -V`.
4. Unchanged vs `version.json` → exit.
5. `nix-prefetch-url` the release's `monolithic.patch` → SRI hash → rewrite `version.json`.
6. **Evaluate** the derivation (`nix eval ... .drvPath`) — catches bad hashes, bad
   tags, config-syntax regressions. Cannot build (runner limits), and does not need to.
7. Commit + push only on successful evaluation.

---

## 7. Part D — `modules/server/kernel-builder.nix` (device-agnostic)

```nix
vexos.server.kernelBuilder = {
  enable          = true;
  kernels         = [ "ogc" ];          # enum from the registry
  schedule        = "*-*-* 01:00:00";   # overnight
  repoPath        = "/etc/nixos";
  gcRootDir       = "/var/lib/harmonia/roots";
  keepGenerations = 3;
};
```

**Assertion:** `vexos.server.harmonia.enable` must be true — building without
serving accomplishes nothing, and the user's intent is explicitly "a kernel
option that can be enabled on Harmonia." Message names the fix.

Per kernel, a `systemd.services.kernel-build-<name>` (`Type=oneshot`):

1. `git -C <repoPath> pull --ff-only`
2. Evaluate that kernel's `drvPath` from the current checkout
3. Output path already in the store → exit 0 (no-op; the common case)
4. `nix build` it (hours)
5. On success: `nix-store --add-root <gcRootDir>/<name>-<version>` — **this is
   what prevents `min-free`/`max-free` GC (`modules/nix.nix:137`) from deleting
   the kernel out from under Harmonia**
6. Prune roots beyond `keepGenerations` (previous kernels stay pinned → rollback)
7. On failure: previous GC root untouched; last-known-good kernel keeps serving

`systemd.timers.kernel-build-<name>`: `OnCalendar = cfg.schedule`,
`Persistent = true` (catches up after downtime), per `joplin-postgres-dump`.

**`just` recipes** (kernel name defaults to the single enabled one):
- `just kernel-build-now [name]` — manual trigger, mirroring `just backup-now`
- `just kernel-build-status` — running? elapsed? last result? pinned version?
- `just kernel-build-log [name]` — `journalctl -fu kernel-build-<name>`

---

## 8. Part E — Desktop consumption

New `modules/system-custom-kernel.nix`:

```nix
vexos.features.kernel = {
  enable = true;
  name   = "ogc";   # enum from the registry; extensible
};
```

`vexos.features.*` namespace, registered in `_feature_names` so
`just enable-feature kernel` works — matching every other toggle. (The reverted
CachyOS attempt used `vexos.kernel.*` and had to be corrected; not repeating that.)

Priority `lib.mkOverride 90`, slotting into the ladder verified earlier this session:

```
1000 mkDefault   modules/system.nix
 100 normal      modules/system-latest-kernel.nix
  90 mkOverride  THIS MODULE
  75 mkOverride  modules/zfs-server.nix
  50 mkForce     modules/gpu/vm-guest-additions.nix   ← VM keeps 6.12
```

**Cache-availability guard.** If a desktop rebuilds after a pin bump but before
the builder has finished, Nix silently compiles the kernel locally — hours, on
the workstation. Guard: query Harmonia for the kernel's `.narinfo` and abort with
a clear message if absent. (This narinfo technique was validated live earlier
this session against the CachyOS cache.) Wired into `just update` / `just rebuild`
when `vexos.features.kernel.enable` is set.

---

## 9. Files

**New (8):** `pkgs/kernels/default.nix`, `pkgs/kernels/ogc/{default.nix,config.nix,version.json}`,
`modules/server/kernel-builder.nix`, `modules/system-custom-kernel.nix`,
`.github/workflows/update-kernels-nightly.yml`, this spec.

**Modified (8):** `pkgs/default.nix`, `modules/server/harmonia.nix`,
`modules/nix.nix`, `modules/secrets-sops.nix`, `modules/server/default.nix`,
`modules/server/backup.nix`, `configuration-desktop.nix`, `justfile`.

---

## 10. Risks

| # | Risk | Sev | Mitigation |
|---|------|-----|------------|
| R-1 | ~~Build wall-clock unmeasured~~ | **Not a concern** | Explicitly out of scope per user. Builds are unattended and `Type=oneshot`; systemd skips a timer trigger while the previous run is still active, so even a multi-day build cannot stack. Cadence needs no tuning. |
| R-2 | ~~Config translation is Fedora-entangled~~ | **Low** (was High) | **Retired by the investigation gate**: 173 lines of additive device enablement, base-config agnostic (§0.1). |
| R-3 | nixpkgs bump silently invalidates the built kernel | High | Builder evaluates the *current* derivation, not tags (§3). |
| R-4 | ~~`monolithic.patch` must apply to nixpkgs' base kernel~~ | **Low** (was High) | **Premise was false** (§0.3). OGC tags are pre-patched trees; we set our own `version`/`src` like `linux_xanmod`. No patch application, no version matching. Residual: `modDirVersion` must match the kernel's internal version string (`7.2` → `7.2.0`) — a standard `buildLinux` detail, verified against `/lib/modules` on first build. |
| R-4b | A brand-new upstream kernel may outpace nixpkgs' kernel *build infrastructure* (`common-config.nix` referencing options that moved), breaking the build even though the source is self-contained. | Med | CI **evaluates before committing the pin** (§6 step 6), so a broken version never lands. If a build fails, the previous pin and its GC root keep serving — the Nix package simply stays a release behind until upstream or nixpkgs catches up. This is the user's stated preference: lag is acceptable, breakage is not. |
| R-5 | Desktop compiles locally on cache miss | Med | Narinfo preflight guard (§8). |
| R-6 | Harmonia serves the entire store to the tailnet | Med | Restricted to `tailscale0` (B-1) — authenticated mesh only. Accepted. |
| R-7 | NVIDIA kmods not cached for a custom kernel | Med | Inherent. The builder *could* also build NVIDIA desktop configs — deferred, out of scope. |
| R-8 | OGC is young (formed Jan 2026); no long bug history | Med | ASUS Linux is a founding partner and ASUS WMI/Ally options ship in `ogc.config.set` (§0.1) — favourable for this hardware, still unproven. LTS stream is the escape hatch. |
| R-9 | Losing the Harmonia key breaks all clients | Low | sops-managed; already in `backup.nix`. |
| R-10 | Rebuild races an in-progress build | Low | `Type=oneshot`; GC root moves only after success; old kernel serves throughout. |

---

## 11. Validation

**Phase 2 order** (highest-risk-first, so a dead end is cheap):
1. Confirm `modDirVersion` for the pinned tag and that `buildLinux` accepts the
   OGC source as-is (R-4 residual). Cheapest possible check; do it first.
2. Translate the 173 config lines into `structuredExtraConfig`.
3. Build once manually to confirm the whole path end-to-end.

**Static / evaluation (WSL; `nix` present, NixOS not required):**
```bash
nix flake show --impure
nix build --dry-run --impure .#nixosConfigurations.vexos-desktop-amd.config.system.build.toplevel
nix eval --impure .#nixosConfigurations.vexos-desktop-amd.config.boot.kernelPackages.kernel.version
bash scripts/preflight.sh          # must exit 0
```
Never `nix flake check` (FORBIDDEN COMMANDS).

**Runtime, on the builder host:**
```bash
just enable harmonia && just rebuild
just harmonia-info
just kernel-build-now ogc
just kernel-build-log ogc          # record wall-clock → R-1
```

**Runtime, on a desktop:** `just enable-feature kernel && just update` — expect a
download, not a compile. Confirm with `uname -r` after reboot.
