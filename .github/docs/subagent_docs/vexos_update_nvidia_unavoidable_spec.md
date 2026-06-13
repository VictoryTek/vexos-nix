# Spec: vexos-update — reclassify unfree NVIDIA userspace + patched openrazer as unavoidable

## Current state

`modules/nix.nix` embeds the `vexos-update` shell script. It classifies local builds into:
- **HEAVY** (`HEAVY_BUILD_REGEX`) → block update, restore flake.lock, exit 2
- **NON_HEAVY** → allow, log as `VEXOS_LOCAL_BUILD:`

`HEAVY_BUILD_REGEX` at line 225 (and a duplicate at line 178 in the kernel-override check):
```
'^(linux-[0-9][^/]*-modules|linux-[0-9][^/]*-modules-shrunk|NVIDIA-Linux-|nvidia-x11-|nvidia-settings-|openrazer-[0-9])'
```

This means any NVIDIA driver update or openrazer package update causes `just update` to **block**
(restore lock, exit 2, print "run `just update-all`"). The user must run `just update-all` every time
NVIDIA's driver bumps.

## Problem

As confirmed empirically in the preceding session (nvidia_open_cache_and_latest_kernel):

- `nvidia-x11` (proprietary userspace libGL/X driver) is **unfree and non-redistributable** — Hydra
  never builds or caches it at any nixpkgs revision, channel, or time. There is no future state where
  `just update` would find it cached and stop blocking.
- `NVIDIA-Linux-*.run`, `nvidia-settings-`, `nvidia-persistenced-` — same reason.
- `openrazer-[0-9]` patched via local `overrideAttrs` in `modules/razer.nix` — patched derivations
  have a different hash from anything Hydra built; also structurally never cached.

Blocking on these derivations is equivalent to permanently disabling `just update` for every NVIDIA
desktop host.

The open kernel module (`nvidia-open-*`) IS cached (GPL/MIT, Hydra builds it) and is already used.

## Proposed solution

Split the single regex into two:

1. **`HEAVY_BUILD_REGEX`** — packages that ARE cacheable but take hours; block if not in cache:
   ```
   '^(linux-[0-9][^/]*-modules|linux-[0-9][^/]*-modules-shrunk)'
   ```

2. **`UNAVOIDABLE_REGEX`** — packages that are NEVER cached; proceed with informational message:
   ```
   '^(NVIDIA-Linux-|nvidia-x11-|nvidia-settings-|nvidia-persistenced-|openrazer-[0-9])'
   ```

Partition `ALL_LOCAL` into three groups:
- `HEAVY_BUILDS` → block (kernel module cache miss; retry in 1-3 days)
- `UNAVOIDABLE_BUILDS` → log as `VEXOS_LOCAL_BUILD:` with explanation; continue
- `NON_HEAVY_BUILDS` → log as `VEXOS_LOCAL_BUILD:`; continue (existing behaviour)

Also fix the duplicate `HEAVY_BUILD_REGEX` in the kernel-override-clear block (line 178) — it checks
whether the target kernel modules are now cached; NVIDIA presence in that check is irrelevant to the
kernel-override question and should be removed.

## Scope

Single file: `modules/nix.nix`

Two locations within the `vexos-update` script:
1. Lines ~178–181: `STILL_HEAVY` regex in the kernel-override-clear block
2. Lines ~225–257: main `HEAVY_BUILD_REGEX` + partition + block message

## Risks / mitigations

- `VEXOS_UPDATE_STRICT=1` mode: in strict mode, block everything (including UNAVOIDABLE). This is
  an advanced escape hatch and doesn't change.
- The `VEXOS_CACHE_BLOCK:` message currently says "kernel or NVIDIA packages". Update to say "kernel
  packages" only, since NVIDIA will no longer reach that branch.
- No other files are affected — `install.sh` already has the correct `UNAVOIDABLE_REGEX` treatment.

## Implementation steps

1. In the kernel-override-clear block: replace `HEAVY_BUILD_REGEX` with `KERNEL_BLOCK_REGEX`
   (kernel modules only) so the "is target kernel cached?" question isn't contaminated by NVIDIA.
2. In the main update block: add `UNAVOIDABLE_REGEX`; change partition to three-way; add
   `UNAVOIDABLE_BUILDS` informational output block before the `NON_HEAVY_BUILDS` block.
3. Update `VEXOS_CACHE_BLOCK:` message to remove NVIDIA reference.
4. Update the inline comment block to document the three-way partition.
