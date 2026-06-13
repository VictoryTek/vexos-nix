# Spec: NVIDIA Driver Double-Fallback for install.sh

## Current State

`install.sh` has a two-stage build strategy for NVIDIA desktop installs:

1. **First dry-build**: detects "will be built" derivations that are missing from the binary cache.
2. **Kernel fallback (stage 1)**: if all cache misses match `HEAVY_BUILD_REGEX` (NVIDIA/OpenRazer packages), writes `kernel-install-override.nix` with `boot.kernelPackages = lib.mkForce pkgs.linuxPackages` and re-runs dry-build.
3. **REMAINING check**: if the second dry-build still shows misses, abort.

## Problem

The `REMAINING` check (lines 471–489 of `scripts/install.sh`) does **not** apply `HEAVY_BUILD_REGEX` filtering. When NVIDIA 580.x bumps in nixpkgs before Hydra has built it for _any_ kernel, the following packages appear in `REMAINING`:

```
NVIDIA-Linux-x86_64-580.142.run.drv   ← driver installer, no kernel suffix
nvidia-x11-580.142-6.12.92.drv        ← kernel module for linuxPackages
nvidia-settings-580.142.drv           ← settings GUI, no kernel suffix
```

All three match `HEAVY_BUILD_REGEX`, but since `REMAINING` is non-empty the install aborts with "wait 24 hours." The kernel swap reduced misses (openrazer resolved) but cannot help when the NVIDIA driver _version_ itself is uncached.

## Proposed Solution — Driver Double-Fallback

Add a **stage 2 fallback**: when `REMAINING` after the kernel fallback contains _only_ HEAVY (NVIDIA) items, upgrade `kernel-install-override.nix` to also set `vexos.gpu.nvidiaDriverVariant = "legacy_535"`.

NVIDIA 535.x has been in nixpkgs for 2+ years and is always available in the binary cache for any stable kernel. A third dry-build confirms the combo is fully cached before proceeding.

After install, `just update` / the Up app removes the override and upgrades to the target driver once 580 lands in Hydra's cache.

### Conditions for driver fallback

- `REMAINING` is non-empty
- All items in `REMAINING` match `HEAVY_BUILD_REGEX` (only NVIDIA packages, no other packages)
- `VARIANT = "nvidia"` AND `NVIDIA_SUFFIX = ""` (user chose Latest; not already on 535)

If conditions not met → existing abort path (non-NVIDIA packages can't be helped by a driver swap).

## Implementation Steps

### 1. `scripts/install.sh` — Replace the `if [ -n "$REMAINING" ]` block (lines 471–489)

Replace with three-branch logic:

```
if REMAINING non-empty:
  compute REMAINING_NON_NVIDIA (REMAINING filtered by HEAVY_BUILD_REGEX)
  if REMAINING_NON_NVIDIA empty AND variant=nvidia AND suffix="":
    print driver-not-cached warning
    upgrade kernel-install-override.nix to add vexos.gpu.nvidiaDriverVariant = "legacy_535"
    git add -f kernel-install-override.nix
    third dry-build → REMAINING2
    if REMAINING2 non-empty:
      cleanup + abort with standard message
    print "✓ All packages available (using fallback kernel + NVIDIA 535 LTS)."
  else:
    cleanup + abort with standard message (non-NVIDIA packages)
else:
  print "✓ All packages available (using channel-default kernel)."
```

### 2. `scripts/install.sh` — Update post-install note (lines 531–536)

When `kernel-install-override.nix` contains `nvidiaDriverVariant`, mention both fallbacks in the note:

> "Note: installed with channel-default kernel and NVIDIA 535 LTS driver."

Otherwise keep existing: "Note: installed with channel-default kernel (linuxPackages)."

### 3. `kernel-install-override.nix` content for double-fallback

```nix
# Written by vexos-nix installer — NVIDIA 580 and target kernel not yet in cache.
# Temporarily falls back to channel-default kernel and NVIDIA 535 LTS driver.
# Removed automatically by vexos-update once target packages are cached.
# To upgrade manually: delete this file, then run: just update
{ lib, pkgs, ... }:
{
  boot.kernelPackages = lib.mkForce pkgs.linuxPackages;
  vexos.gpu.nvidiaDriverVariant = "legacy_535";
}
```

`lib.mkForce` is required for `boot.kernelPackages` (set at priority 100 in
`system-desktop-kernel.nix`). Plain assignment suffices for `nvidiaDriverVariant`
(option default at priority 1500, overridden by normal priority 100).

## Files Modified

- `scripts/install.sh` (lines 471–489 and 531–536)

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| User has Maxwell/Pascal GPU that doesn't support 580 open modules | N/A — 535 LTS also works on these GPUs; no regression |
| `vexos.gpu.nvidiaDriverVariant` option not available in override context | Option is declared in `modules/gpu/nvidia.nix` which is imported via `gpuNvidia` module for all nvidia variants; available in the module system |
| `mkStatelessVariant` / `mkHtpcVariant` don't include `kernelOverrideFile` | Driver fallback is gated by `[ "$ROLE" = "desktop" ]`, same as the existing kernel fallback — no new exposure |
| 535 LTS also not cached (extremely unlikely) | Third dry-build catches it; falls through to standard abort |
