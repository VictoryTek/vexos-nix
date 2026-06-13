# Spec: Fix query_cached_nvidia_variant — allowUnfree required for NVIDIA eval

## Problem

`query_cached_nvidia_variant` evaluates `nvidiaPackages.stable.outPath` via:

```
.legacyPackages.x86_64-linux.linuxPackages.nvidiaPackages.${nv_attr}.outPath
```

`legacyPackages` does not accept a nixpkgs `config` argument. NVIDIA packages
require `config.allowUnfree = true` and `config.nvidia.acceptLicense = true` to
evaluate; without them nixpkgs throws an unfree-package error. That error is
swallowed by `2>/dev/null`, `out_path` is empty, `[ -z "$out_path" ] && continue`
skips both candidates, and the function returns empty — triggering the "no version
cached" abort even when legacy_535 IS available in the cache.

## Fix

Replace `.legacyPackages.x86_64-linux.${kpkg}.nvidiaPackages.${nv_attr}.outPath`
with a direct `import` of the nixpkgs source with explicit config:

```nix
(import (builtins.getFlake "git+file:///etc/nixos").inputs.nixpkgs.outPath {
  system = "x86_64-linux";
  config.allowUnfree = true;
  config.nvidia.acceptLicense = true;
}).${kpkg}.nvidiaPackages.${nv_attr}.outPath
```

`(builtins.getFlake url).inputs.nixpkgs.outPath` gives the Nix store path of
the pinned nixpkgs source. `import`ing it with config correctly allows unfree
packages, so `nvidiaPackages.stable` evaluates to a derivation with `.outPath`.

## Files Modified

- `scripts/install.sh`
