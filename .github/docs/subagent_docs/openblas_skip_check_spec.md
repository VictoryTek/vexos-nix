# Spec: Skip OpenBLAS checkPhase

## Current State
`openblas-0.3.33` test #30 (`xzcblat3`) hangs indefinitely during `nixos-rebuild` on `vexos-desktop-nvidia`.
Reproducible for 2 days. Test #29 passed in 24.59s; test #30 never completes.

## Problem
The OpenBLAS test suite (CTest) runs in Nix's sandboxed build environment. On this hardware/kernel combination,
test `xzcblat3` (complex double-precision BLAS level 3) stalls with only 2 cores at <50% load — indicating a
deadlock or starvation condition inside the test, not a compute-bound hang.

## Solution
Add a `nixpkgs.overlays` entry via an inline NixOS module that overrides `openblas` with `doCheck = false`.
This skips the test suite without changing the compiled library in any way.

## Implementation
- Add `openblasNoCheckModule` inline in `flake.nix`
- Add to `commonBase` so it applies to all non-vanilla roles

## Risks
- Low: `doCheck = false` is a standard nixpkgs escape hatch for hanging tests
- The openblas binary is identical to what the binary cache would supply
- Vanilla role not covered (doesn't use commonBase), acceptable since vanilla has no special GPU config
