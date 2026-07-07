# L-19 — `intel-media-driver` shipped in all GPU closures

Status: Phase 1 (Research & Specification)
Source: MASTER_PLAN L-19 (ARCH 5.2) · `modules/gpu.nix:18` (current: line 17)

## Current State

`modules/gpu.nix` (the file's own header: "Common GPU base... GPU-brand-specific
configuration lives in modules/gpu/{amd,nvidia,vm}.nix") includes
`intel-media-driver` in its universal `hardware.graphics.extraPackages` list,
with a comment acknowledging the problem directly: "harmless on AMD/NVIDIA".
This file is imported by every role that has a GPU variant (desktop, server,
headless-server, htpc, stateless — confirmed via grep across
`configuration-*.nix`), so every AMD/NVIDIA/VM host closure ships an
Intel-specific VA-API driver it can never use.

`modules/gpu/intel.nix` already knows about this dependency — its own
comment says "intel-media-driver is already included via modules/gpu.nix
extraPackages" — it only adds the *32-bit* variant itself
(`extraPackages32`), relying on the shared base for the 64-bit package.
`modules/gpu/intel-headless.nix` has the identical implicit reliance (no
`intel-media-driver` entry of its own at all). Confirmed via grep that no
other GPU-brand file (`amd.nix`, `nvidia.nix`, `vm.nix`, `amd-headless.nix`,
`nvidia-headless.nix`, `vanilla-vm.nix`) references or depends on it.

## Problem Definition

An Intel-only package ships in every non-Intel GPU closure, violating this
file's own stated "common base, brand-specific stuff goes in
modules/gpu/*.nix" architecture.

## Proposed Solution

Remove `intel-media-driver` from `modules/gpu.nix`'s shared list; add it
explicitly to both Intel-specific files that currently rely on the shared
inclusion (`modules/gpu/intel.nix`, `modules/gpu/intel-headless.nix`),
updating `intel.nix`'s now-stale comment accordingly.

## Implementation Steps

1. `modules/gpu.nix` — remove the `intel-media-driver` line from
   `extraPackages`.
2. `modules/gpu/intel.nix` — add `intel-media-driver` to its own
   `extraPackages` list; update the comment that referenced the shared
   base.
3. `modules/gpu/intel-headless.nix` — add `intel-media-driver` to its own
   `extraPackages` list.

## Configuration Changes

None visible on Intel hosts (package moves, doesn't disappear). AMD/NVIDIA/VM
hosts lose one package from their closure — a pure reduction, not a
behavior change (verified no other file references it).

## Risks and Mitigations

- **Risk:** an Intel host's closure could lose `intel-media-driver`
  entirely if the addition to `intel.nix`/`intel-headless.nix` is missed.
  **Mitigation:** verified via `extendModules` (or direct package-set
  inspection) that `hardware.graphics.extraPackages` on an Intel desktop
  and Intel headless-server host still contains `intel-media-driver`
  after the move.
- **Risk:** an AMD/NVIDIA/VM host could regress if something unexpectedly
  depended on `intel-media-driver` being present.
  **Mitigation:** confirmed via grep that no other GPU-brand file
  references it; also confirmed via `extendModules` that the package is
  now genuinely absent from a non-Intel closure's `extraPackages` list.
