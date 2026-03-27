# Spec: CachyOS Pre-built Kernel — Binary Cache Fix

**Date:** 2026-03-27  
**Author:** Research Agent  
**Scope:** `flake.nix`, `template/etc-nixos-flake.nix`

---

## 1. Current State Analysis

### 1.1 Kernel configuration

`modules/performance.nix` sets:

```nix
boot.kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-bore;
```

`pkgs.cachyosKernels` is injected by an overlay. In `flake.nix` there are **two separate code paths** that define this overlay:

| Code path | Location | Overlay used |
|---|---|---|
| Direct builds (`vexos-amd`, `vexos-nvidia`, …) | `cachyosOverlayModule` in `flake.nix` | `nix-cachyos-kernel.overlays.default` |
| Template path (`/etc/nixos → nixosModules.base`) | Inline in `nixosModules.base` in `flake.nix` | `nix-cachyos-kernel.overlays.default` |

Both use `overlays.default`.

### 1.2 Binary caches configured in `nix.settings`

`configuration.nix` (the `nix.settings` block) currently specifies:

```
substituters:
  https://cache.nixos.org
  https://nix-gaming.cachix.org
  https://attic.xuyh0120.win/lantian   ← primary CachyOS Hydra cache
  https://cache.garnix.io              ← fallback Garnix CI cache

trusted-public-keys:
  cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=
  nix-gaming.cachix.org-1:nbjlureqMbRAxR1gJ/f3hxemL9svXaZF/Ees8vCUUs4=
  lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc=
  cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g=
```

### 1.3 Flake input

```nix
nix-cachyos-kernel = {
  url = "github:xddxdd/nix-cachyos-kernel/release";
  # intentionally no nixpkgs.follows — per upstream documentation
};
```

Using the `release` branch is correct: the release branch is only advanced when CI has successfully built and pushed all kernel variants to the binary cache.

### 1.4 Template flake

`template/etc-nixos-flake.nix` (placed at `/etc/nixos/flake.nix` on fresh installs) contains no `nixConfig` block.

---

## 2. Research Findings

### 2.1 Chaotic-Nyx — DEAD, do not use

**`github:chaotic-cx/nyx` was archived on 2025-12-08 and is now read-only.** It cannot be used as a CachyOS kernel source going forward. This option is eliminated.

### 2.2 xddxdd/nix-cachyos-kernel — authoritative source

This is the correct and actively maintained source. Key facts from the upstream README:

- **`release` branch**: Only advanced when Hydra CI has built all outputs and pushed them to `attic.xuyh0120.win/lantian`. This is the right branch for binary-cache-first installs.
- **`overlays.default`**: Applies CachyOS kernel packages on top of the **host's nixpkgs** instance. The kernel source pins are internal to nix-cachyos-kernel, but the **build-time inputs** (compiler toolchain, glibc, kernel headers from nixpkgs) come from the host's pinned nixpkgs revision.
- **`overlays.pinned`**: Creates a second nixpkgs instance using the exact nixpkgs revision pinned inside nix-cachyos-kernel. The entire kernel build — source, toolchain, and all dependencies — is evaluated from this internal revision, which is the **same revision CI used** when building and caching the kernel.
- Per the README (updated 2026-03-01): "Use `pinned` if you want to **ensure that you can fetch kernel from binary cache**."

**Binary caches (sourced directly from upstream README):**

| Cache | URL | Public key | Reliability |
|---|---|---|---|
| Primary | `https://attic.xuyh0120.win/lantian` | `lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc=` | Personal Hydra CI; high reliability for `release` branch |
| Fallback | `https://cache.garnix.io` | `cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g=` | Garnix free plan; may be exhausted mid-month |

### 2.3 `nix.settings.substituters` vs `nix.settings.trusted-substituters`

| Setting | Effect | When it takes effect |
|---|---|---|
| `nix.settings.substituters` | Caches consulted by the Nix daemon for **all** builds. Written to `/etc/nix/nix.conf` as `substituters`. | Only after a successful NixOS rebuild activates the configuration. |
| `nix.settings.trusted-substituters` | A whitelist of caches that **unprivileged users** may add to their own `~/.config/nix/nix.conf`. Does not add them automatically. | Same — only after rebuild. |

Neither solves the bootstrapping problem. On a fresh machine `/etc/nix/nix.conf` only contains `cache.nixos.org` (the NixOS default). Custom substituters written by `nix.settings` are not active until the first rebuild completes — but the first rebuild is exactly when the kernel needs to be fetched.

### 2.4 The `nixConfig` flake attribute

A flake can carry cache hints in a top-level `nixConfig` attribute:

```nix
{
  nixConfig = {
    extra-substituters = [ "https://example.cachix.org" ];
    extra-trusted-public-keys = [ "example.cachix.org-1:..." ];
  };
  ...
}
```

When a Nix command (including `nixos-rebuild`) processes a flake containing `nixConfig`:
- Without `--accept-flake-config`: The user is prompted interactively to accept the extra caches.
- With `--accept-flake-config`: Extra caches are accepted silently and consulted immediately, **before any NixOS module evaluation occurs**.

This mechanism is evaluated at the **flake layer** — entirely before `nix.settings` modules take effect. It is therefore the correct tool for the bootstrapping problem.

**Important scoping rule**: `nixConfig` only applies to the **top-level flake** being built. A `nixConfig` in an input flake (`vexos-nix/flake.nix`) does **not** propagate to the wrapper flake that consumes it (`/etc/nixos/flake.nix`). Therefore:

- Adding `nixConfig` to `vexos-nix/flake.nix` helps when building directly from the repo (developers, CI).
- Adding `nixConfig` to `template/etc-nixos-flake.nix` is required to solve the bootstrapping problem on fresh installs, since that file is the top-level flake for `/etc/nixos#vexos-*` builds.

---

## 3. Root Cause

The kernel compiles from source due to **two independent failure modes** that each independently cause compilation. Both must be resolved.

### Root Cause 1 — Derivation hash mismatch (primary)

**`overlays.default` produces a different store path hash than what CI cached.**

When the `default` overlay is used:
1. The overlay applies CachyOS kernel derivations to vexos-nix's nixpkgs instance.
2. The resulting derivation is hashed against vexos-nix's **nixpkgs revision** (e.g., `nixos-25.11` pinned in `flake.lock`).
3. The CI (Hydra, Garnix) builds using nix-cachyos-kernel's **internally pinned nixpkgs revision**, which is different.
4. Different build inputs → different Nix derivation hash → **cache miss** → local compilation.

This failure mode affects **every rebuild**, fresh or otherwise, as long as the two nixpkgs revisions differ.

### Root Cause 2 — Bootstrapping gap (secondary)

**The CachyOS binary caches are unknown to the Nix daemon on a fresh machine.**

On first install:
1. `/etc/nix/nix.conf` only contains `https://cache.nixos.org`.
2. `nix.settings.substituters` only writes to `/etc/nix/nix.conf` upon successful activation — which hasn't happened yet.
3. The Nix daemon never consults `attic.xuyh0120.win/lantian` or `cache.garnix.io`.
4. Even if Root Cause 1 were fixed (correct hash), the daemon wouldn't know where to fetch the pre-built kernel, so it compiles locally.

This failure mode affects **first installs only** but is guaranteed to manifest.

---

## 4. Proposed Solution

**Minimal two-part fix.** No new dependencies, no flake inputs, no structural reorganisation.

### Part A — Switch to `overlays.pinned` (fixes Root Cause 1)

Replace `nix-cachyos-kernel.overlays.default` with `nix-cachyos-kernel.overlays.pinned` in both overlay application sites inside `flake.nix`.

The `pinned` overlay initialises a second nixpkgs instance using the exact revision pinned inside nix-cachyos-kernel. The resulting derivation hash matches what CI built and pushed to the binary cache, guaranteeing a cache hit on every rebuild once the caches are reachable.

**Tradeoffs:**
- ✅ Derivation hash guaranteed to match CI → always fetched, never compiled.
- ✅ Kernel build guaranteed compatible with the CachyOS patch set.
- ⚠️ Creates a second nixpkgs evaluation instance → slightly higher memory use during `nixos-rebuild` evaluation.
- `nixpkgs.config` options (e.g., `allowUnfree`) from the host may not propagate into the pinned nixpkgs for the kernel build. This is acceptable because CachyOS kernel packages are FOSS (GPL) and do not require `allowUnfree`.

### Part B — Add `nixConfig` to both flakes (fixes Root Cause 2)

Add a `nixConfig` attribute to:
1. `flake.nix` — effective for direct builds from the repo.
2. `template/etc-nixos-flake.nix` — effective for fresh installs using the template.

The `nixConfig` block instructs `nix` (and `nixos-rebuild`) to use the CachyOS caches before any NixOS module evaluation. Combined with `--accept-flake-config` in the template's install instructions, this ensures the Nix daemon consults the right caches on the very first rebuild.

---

## 5. Implementation Steps

### 5.1 Modify `flake.nix`

**Step 1 — Add `nixConfig` block** at the very top of the flake (before `description`):

```nix
{
  nixConfig = {
    extra-substituters = [
      "https://attic.xuyh0120.win/lantian"
      "https://cache.garnix.io"
    ];
    extra-trusted-public-keys = [
      "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc="
      "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
    ];
  };

  description = "vexos-nix — Personal NixOS configuration";
  ...
```

**Step 2 — Fix `cachyosOverlayModule`** (used by direct builds: `vexos-amd`, `vexos-nvidia`, etc.):

Old:
```nix
cachyosOverlayModule = {
  nixpkgs.overlays = [ nix-cachyos-kernel.overlays.default ];
};
```

New:
```nix
cachyosOverlayModule = {
  # overlays.pinned uses nix-cachyos-kernel's internally pinned nixpkgs revision,
  # guaranteeing the derivation hash matches what CI built and cached.
  nixpkgs.overlays = [ nix-cachyos-kernel.overlays.pinned ];
};
```

**Step 3 — Fix `nixosModules.base`** (used by template `/etc/nixos/flake.nix` path):

Old (inside the `base` module's `nixpkgs.overlays`):
```nix
nix-cachyos-kernel.overlays.default
```

New:
```nix
nix-cachyos-kernel.overlays.pinned
```

### 5.2 Modify `template/etc-nixos-flake.nix`

**Step 1 — Add `nixConfig` block** at the very top of the template flake (before `inputs`):

```nix
{
  # Instruct nix/nixos-rebuild to consult CachyOS binary caches during evaluation,
  # before NixOS modules activate nix.settings. This ensures the CachyOS kernel
  # is fetched (not compiled) even on a fresh machine.
  # Run with --accept-flake-config to silence the interactive trust prompt.
  nixConfig = {
    extra-substituters = [
      "https://attic.xuyh0120.win/lantian"
      "https://cache.garnix.io"
    ];
    extra-trusted-public-keys = [
      "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc="
      "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
    ];
  };

  inputs = {
  ...
```

**Step 2 — Update setup instructions in the template's header comment** to use `--accept-flake-config`:

Old:
```
   2. Apply using the variant that matches your hardware:
        sudo nixos-rebuild switch --flake /etc/nixos#vexos-amd
```

New:
```
   2. Apply using the variant that matches your hardware:
        sudo nixos-rebuild switch --flake /etc/nixos#vexos-amd --accept-flake-config
```

(Same update for `vexos-nvidia`, `vexos-intel`, `vexos-vm` examples in the comment.)

---

## 6. Files to Modify

| File | Changes |
|---|---|
| `flake.nix` | Add `nixConfig` block; change both `.overlays.default` → `.overlays.pinned` |
| `template/etc-nixos-flake.nix` | Add `nixConfig` block; update rebuild commands in header comment to include `--accept-flake-config` |

No other files require modification.

---

## 7. Risks and Tradeoffs

### 7.1 Dual nixpkgs evaluation overhead

`overlays.pinned` instantiates a second nixpkgs. During `nixos-rebuild` evaluation this means two nixpkgs instances are in memory. In practice, nix evaluation is efficient about sharing, and kernel builds are themselves long — the evaluation overhead is negligible compared to kernel download time. This is the standard upstream recommendation for binary-cache-first usage.

### 7.2 Garnix fallback reliability

The Garnix free plan has monthly build minute quotas. The upstream README notes: "If you see 'all builds failed' from Garnix, it means I ran out of free plan's build time." In that case `https://attic.xuyh0120.win/lantian` is the primary cache and the fallback silently 404s. Since `attic.xuyh0120.win/lantian` is backed by a personal Hydra instance and the `release` branch is only advanced when CI succeeds, the primary cache should always have the build. The Garnix fallback is optional but harmless to keep.

### 7.3 `nixConfig` requires user acceptance on first build

Without `--accept-flake-config`, nix will interactively ask whether to trust the extra caches. For automated installs or scripts, the flag should be explicitly passed. The template header is updated to reflect this. For interactive fresh installs this is a one-time prompt that is acceptable UX.

### 7.4 Upstream `release` branch availability

The fix depends on `attic.xuyh0120.win/lantian` being reachable. This is a third-party server. If it goes offline, the fallback is Garnix, then local compilation. The current `configuration.nix` already lists both caches as a belt-and-suspenders approach, which is correct.

### 7.5 `nixConfig` does not propagate through flake inputs

The `nixConfig` in `vexos-nix/flake.nix` is only effective when building directly from that flake. It does not propagate when the template (`/etc/nixos/flake.nix`) is the top-level flake. This is why both files must be updated independently — a fact confirmed by the NixOS wiki and Nix flake documentation.

---

## 8. Alternative Approaches Considered and Rejected

| Alternative | Reason rejected |
|---|---|
| **Chaotic-Nyx** (`github:chaotic-cx/nyx`) | Archived and dead as of 2025-12-08. |
| **Manually pre-seed `/etc/nix/nix.conf`** on fresh install | Requires manual steps not documented in the template. Error-prone. Does not solve the root cause. |
| **`nix.settings.trusted-substituters`** instead of `nixConfig` | These only whitelist caches for unprivileged users; they do not add caches automatically. Boot strapping problem remains. |
| **`overlays.default` with `--option substituters` flags** | Requires modifying the nixos-rebuild invocation every time. Does not solve the hash mismatch root cause. |
| **Pin vexos-nix nixpkgs to match nix-cachyos-kernel's pinned nixpkgs** | Would require removing `nixpkgs-unstable` or creating a complex double-pinning scheme. Fragile and must be manually kept in sync on every nix-cachyos-kernel update. |

---

## 9. Validation Checklist

After implementation, verify:

- [ ] `nix flake check` passes.
- [ ] `sudo nixos-rebuild dry-build --flake .#vexos-amd` completes without building kernel from source (check for "fetching" vs "building" output for `linux-cachyos-bore`).
- [ ] `sudo nixos-rebuild dry-build --flake .#vexos-nvidia` same.
- [ ] `sudo nixos-rebuild dry-build --flake .#vexos-intel` same.
- [ ] On a fresh VM (`vexos-vm`), confirm `nixos-rebuild switch --flake /etc/nixos#vexos-vm --accept-flake-config` does not compile the kernel (vm.nix overrides to LTS, so this validates the template `nixConfig` path independently of the kernel fix).
- [ ] Confirm `hardware-configuration.nix` is NOT present in the repo.
- [ ] Confirm `system.stateVersion` is unchanged at `"25.11"`.
