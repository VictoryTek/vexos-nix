# Update Strategy Analysis — vexos-nix

**Type:** Research & Analysis (Phase 1)
**Date:** 2026-06-26
**Scope:** Why update blocks happen, what we pull from unstable, how we compare to
default NixOS and to non-NixOS distros (Bazzite, CachyOS), and a ranked path forward.

---

## 1. Current State Analysis

### 1.1 Channel posture (verified, not assumed)

| Input | flake.nix declares | flake.lock node | Locked ref | Role |
|-------|--------------------|------------------|-----------|------|
| `nixpkgs` (root) | `nixos-26.05` | `nixpkgs_2` | **nixos-26.05** (rev 667d5cf1) | **System base — stable, Hydra-gated channel** |
| `nixpkgs-unstable` | `nixos-unstable` | `nixpkgs-unstable` | nixos-unstable (rev 567a49d1) | Narrow overlay → `pkgs.unstable.*` |
| `nixpkgs` (node, ref `nixos-unstable`, rev e4bae1bd) | — | transitive | from another input | **NOT our base** (common confusion) |

**Correction to a common misread:** the lock node literally named `nixpkgs` carries
`ref = nixos-unstable`, but that is a *transitive* dependency of another flake (proxmox /
vexboard chain). The root system input resolves to node `nixpkgs_2` = **nixos-26.05**.
We are on the **stable channel branch**, which only advances after Hydra has built the
jobset — i.e. cache.nixos.org has *most* of it by the time the ref moves.

### 1.2 What we actually pull from unstable

Only **five** concrete packages use the `pkgs.unstable.*` overlay:

| Package | Location | Reason for unstable |
|---------|----------|---------------------|
| `gnome-boxes` | configuration-desktop.nix:46 | latest GNOME app |
| `nodejs` | home-desktop.nix:24 | latest LTS (nodejs_25 EOL'd) |
| `vscode-fhs` | home-desktop.nix:61 | FHS env + freshness |
| `papermc` | modules/server/papermc.nix:35 | fast-moving Minecraft server |
| `seerr` | modules/server/seerr.nix:47 | fast-moving *arr companion |

The overlay surface is small and deliberate. **None of these are kernel/driver-class
packages**, so none of them are what triggers the update blocks (see §2).

**Doc drift found (not a bug, worth fixing):**
- `flake.nix` comment claims `modules/gnome.nix` consumes `pkgs.unstable` for GNOME apps —
  `grep` finds no such usage. Stale comment.
- `CLAUDE.md` Project Context says "NixOS 25.11"; the flake is on **26.05**.

### 1.3 How the update system works today

`just update` and the Up GUI both call one script: **`vexos-update`** (defined in
`modules/nix.nix`). Its pipeline:

1. Ensure `/etc/nixos` is a git repo (so `git+file://` excludes `secrets/` from the store).
2. Auto-clear a kernel install-override once the target kernel is cached.
3. `cp flake.lock flake.lock.bak` (backup).
4. `nix flake update` → bumps **every** input to its branch tip.
5. `nixos-rebuild dry-build` → parse "will be built" derivations.
6. **Three-way classifier:**
   - `HEAVY_BUILD_REGEX = ^(linux-[0-9]…-modules…)` → **BLOCK**: restore lock, exit 2.
   - `UNAVOIDABLE_REGEX = NVIDIA-Linux-/nvidia-x11-/…/openrazer-[0-9]` → allow (Hydra never
     caches unfree/patched), log `VEXOS_LOCAL_BUILD`.
   - everything else → allow as fast local build.
7. `nixos-rebuild switch`.

Escape hatches already present: `just deploy` (pull config, keep nixpkgs pinned),
`just update-all` (force compile), `just upgrade-analysis <ver>` (read-only preview),
`VEXOS_UPDATE_STRICT=1` (block on all local builds).

### 1.4 Binary cache posture

- Substituters configured: **only `cache.nixos.org`** (plus an *optional*
  `vexos.attic.cacheUrl` that is **null by default** — the plumbing exists but is unused).
- CI (`ci.yml`) **evaluates** all variants (`dry-build`/`nix eval`) but **does not build or
  push** any closure to a cache.
- Net effect: there is **no project-owned cache**. Every NVIDIA host recompiles NVIDIA
  userspace locally; every kernel bump waits on Hydra; every custom `pkgs/` / vexboard build
  is local.

---

## 2. Problem Definition — what is actually "fighting" the user

The friction is **not** the unstable overlay and **not** the choice of stable vs unstable.
It is two specific things:

1. **The kernel-module block (by design).** `nix flake update` jumps `nixos-26.05` to the
   channel HEAD. The channel is gated, but the *last* packages to gate-pass — frequently the
   kernel and its out-of-tree modules — can lag the cache by 1–3 days. When they do,
   `HEAVY_BUILD_REGEX` fires and the **entire update is paused and rolled back**, even
   though all the *config/app* changes were ready. That pause is the "block" the user hits.

2. **No prebuilt cache for the things Hydra will never build for us** (unfree NVIDIA,
   patched OpenRazer, in-tree `pkgs/`, vexboard). These compile locally *every* time on
   *every* host. Plain NixOS desktops without NVIDIA simply never hit this.

---

## 3. Comparison

### 3.1 vs default NixOS (`nixos-rebuild switch --upgrade`)

| Aspect | Default NixOS | vexos-nix | Verdict |
|--------|---------------|-----------|---------|
| Channel | `nixos-26.05`, Hydra-gated | same | **parity** |
| Update bumps to channel tip | yes | yes (`nix flake update`) | **parity** |
| Behaviour on uncached package | silently compiles (slow but completes) | **blocks + rolls back** if kernel-class; else compiles | vexos is *more cautious*, not worse |
| Unfree NVIDIA / DKMS local builds | same (anyone with NVIDIA compiles) | same | **parity** |
| Own binary cache | n/a | option exists, **unused** | gap |

**Conclusion:** vexos has **not meaningfully strayed** from default NixOS in channel choice
or freshness. Where it differs it is *additive safety* (the block prevents accidental
multi-hour kernel compiles). It is **worse only in perceived friction**: default NixOS would
just compile the kernel and finish; vexos stops and makes you wait or run `just deploy`.

### 3.2 vs non-NixOS distros (Bazzite, CachyOS)

- **Bazzite** (rpm-ostree image): the entire OS is **built centrally in CI** and shipped as
  a signed OCI image. The user pulls a finished image — **zero local compilation, ever**.
- **CachyOS** (Arch-based): ships **prebuilt binary repositories** (including their own
  optimised kernels) from their own build farm; `pacman` only downloads.

**The shared lesson:** neither solves lag by picking a "more stable channel." They solve it
by **owning the build infrastructure and shipping prebuilt binaries**, so the end machine
never compiles. The NixOS-native translation of that model is **a self-hosted binary cache
(Attic/Cachix) populated by CI or a builder.**

### 3.3 vs other NixOS-based configs/distros

The standard community answer to exactly this problem is a **Cachix or Attic cache fed by
CI** (nix-community, Garnix, Determinate, and most published flakes do this). Machines add
the cache as a substituter and pull the unfree/patched/custom derivations instead of
compiling. **vexos already has the option scaffolding (`vexos.attic.*`) — it is simply not
wired to a populating builder.**

---

## 4. Proposed Path Forward (ranked, not yet implemented)

### Option A — Project-owned Attic cache fed by a builder *(highest leverage)*
Stand up an Attic cache and have a builder (the existing **server role**, or a self-hosted
CI runner) build `config.system.build.toplevel` for the common variants on each nixpkgs bump
and `attic push`. Desktops set `vexos.attic.cacheUrl`/`publicKey` (already supported) and
pull prebuilt **NVIDIA userspace, kernel, custom pkgs, vexboard** — local compiles and the
kernel block largely disappear. This is the Bazzite/CachyOS model in NixOS form.
- **Tradeoff:** needs a build host. GitHub free runners likely lack the time/disk for full
  NVIDIA+kernel closures; realistically the **VexOS server** becomes the build farm. Real
  infra commitment, but the role already exists.

### Option B — Cache only the kernel so the block stops firing *(targeted)*
If the cache (or a pinned, reliably-cached LTS `boot.kernelPackages`) covers the kernel for
the locked rev, `HEAVY_BUILD_REGEX` never matches and updates flow. Smaller scope than A;
addresses the #1 friction directly. (`cachyos_prebuilt_kernel_spec.md` already explored
adjacent ground.)

### Option C — Soften the block UX *(cheap quick win, low risk)*
Today a kernel-module lag pauses the **whole** update. Instead, on `HEAVY` detection,
auto-fall-back to the **currently running kernel** (same mechanism the install-override
already uses) and apply everything else — so config/app updates land immediately and only
the kernel defers. Alternatively make `just deploy` the one-key suggested path. Directly
removes the day-to-day "fighting" without new infra.

### Option D — Trim unstable surface *(minor housekeeping)*
Re-point `nodejs` / `gnome-boxes` to stable if 26.05 versions are acceptable; keep
`vscode-fhs`/`papermc`/`seerr` on unstable (genuinely fast-moving). Not a cause of blocks —
purely fewer moving parts. Fix the stale `flake.nix`/`CLAUDE.md` doc drift while here.

### Recommendation
- **Now / cheap:** Option C (block UX) + Option D doc fixes — immediate relief, low risk.
- **Strategic:** Option A (own cache via the server role) — the only thing that truly ends
  local compiling, and the closest analogue to how Bazzite/CachyOS avoid this entirely.
- Option B is a subset of A; do it as the first cache target.

---

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Attic builder is real infra to run/maintain | Start with Option C (no infra); add A incrementally, server role first |
| GitHub runners can't build NVIDIA/kernel closures | Use the VexOS server as the build/push host, not CI |
| Auto kernel-fallback (C) masks an intended kernel upgrade | Reuse existing override auto-clear: revert to target once cached |
| Trimming unstable regresses a needed feature | Verify each package's 26.05 version before moving; keep fast-movers on unstable |

---

## 6. Open Decision (for the user)

This spec stops before implementation per the Engineering Principles (present options, do not
silently pick). The path chosen changes scope materially — Option C is a small script edit;
Option A is an infrastructure project. Confirm direction before Phase 2.
