# Spec: Dynamic Cache-Query Fallback + All-Role Kernel Override Support

## Problem Summary

Two distinct gaps exist in the installer's cache-miss fallback strategy:

### Gap 1 — Hardcoded driver version
The NVIDIA driver double-fallback (added in `install_nvidia_driver_fallback`) hardcodes
`legacy_535` as the fallback driver version. When the installer encounters NVIDIA
cache misses that survive the kernel swap, it should instead **query cache.nixos.org**
to find the newest NVIDIA driver version that IS actually built there, and use that.
This avoids stale hardcoding and handles future driver version gaps automatically.

### Gap 2 — Fallback only applies to desktop role
Both the kernel fallback and the driver fallback are gated by `[ "$ROLE" = "desktop" ]`
in `install.sh`. The template flake's `kernelOverrideFile` inclusion is only wired into
`_mkVariantWith` (used by `mkVariant` = desktop). All other roles — `stateless`,
`htpc`, `server`, `headless-server`, `vanilla` — have no fallback protection.

---

## Solution

### 1. `scripts/install.sh` — Replace hardcoded driver fallback with cache query

Add a `query_cached_nvidia_variant` function that:
1. Iterates through NVIDIA variants in nixpkgs in preference order: `stable` → `legacy_535`
2. For each, evaluates the output store path via `nix eval --impure` against the pinned
   nixpkgs from `/etc/nixos`'s resolved inputs
3. Checks the path against `cache.nixos.org` using `nix path-info --store`
4. Returns the vexos variant name (`"latest"` or `"legacy_535"`) for the first cached hit,
   or nothing if neither is cached

The function uses:
```bash
nix --extra-experimental-features 'nix-command flakes' \
  eval --raw --impure \
  "(builtins.getFlake \"git+file:///etc/nixos\").inputs.nixpkgs\
.legacyPackages.x86_64-linux.${kpkg}.nvidiaPackages.${nv_attr}.outPath"
```

Then:
```bash
nix --extra-experimental-features 'nix-command flakes' \
  path-info --store https://cache.nixos.org "$out_path"
```

If no cached variant found, abort with a clear message listing what was checked.

### 2. `scripts/install.sh` — Remove `[ "$ROLE" = "desktop" ]` gate

The fallback block at line 435 is gated by `[ "$ROLE" = "desktop" ]`. Remove this
condition so the kernel fallback (and NVIDIA driver query) applies to all roles.

The `vexos.gpu.nvidiaDriverVariant` set in the override is already guarded by
`[ "$VARIANT" = "nvidia" ] && [ "$NVIDIA_SUFFIX" = "" ]` so non-NVIDIA roles
correctly get a kernel-only override.

### 3. `template/etc-nixos-flake.nix` — Add `kernelOverrideFile` to all builders

`kernelOverrideFile` and `hasKernelOverride` are already declared at the top-level
`let` (lines 131–132). They are only used in `_mkVariantWith` (line 163). Add
`++ lib.optional hasKernelOverride kernelOverrideFile` to:

- `mkStatelessVariant` — after `++ lib.optional hasUserOverride userOverrideFile`
- `mkHtpcVariant` — after `] ++ modules`
- `mkVanillaVariant` — after `] ++ modules`
- `mkHeadlessServerVariant` — after `++ lib.optional hasServices servicesFile`
- `mkServerVariant` — after `++ lib.optional hasServices servicesFile`

---

## Implementation Steps

### install.sh changes

**Step A**: Add `query_cached_nvidia_variant()` function immediately before the
`if [ -n "$SOURCE_BUILDS" ]` block (around line 411).

```bash
# Query cache.nixos.org for the newest NVIDIA driver variant that is available
# for the given kernel packages attribute (default: linuxPackages).
# Prints "latest" or "legacy_535"; returns 1 if neither is cached.
query_cached_nvidia_variant() {
  local kpkg="${1:-linuxPackages}"
  for nv_attr in stable legacy_535; do
    local out_path
    out_path=$(sudo nix --extra-experimental-features 'nix-command flakes' \
      eval --raw --impure \
      "(builtins.getFlake \"git+file:///etc/nixos\").inputs.nixpkgs.legacyPackages.x86_64-linux.${kpkg}.nvidiaPackages.${nv_attr}.outPath" \
      2>/dev/null) || continue
    [ -z "$out_path" ] && continue
    if nix --extra-experimental-features 'nix-command flakes' \
       path-info --store https://cache.nixos.org "$out_path" &>/dev/null 2>&1; then
      case "$nv_attr" in
        stable)     echo "latest"     ;;
        legacy_535) echo "legacy_535" ;;
      esac
      return 0
    fi
  done
  return 1
}
```

**Step B**: Remove `&& [ "$ROLE" = "desktop" ]` from line 435.

**Step C**: Replace the existing driver fallback block (the `if [ -z "$REMAINING_NON_NVIDIA" ]`
section) with a version that calls `query_cached_nvidia_variant` and uses the result
dynamically. The override content becomes:

```nix
{ lib, pkgs, ... }:
{
  boot.kernelPackages = lib.mkForce pkgs.linuxPackages;
  vexos.gpu.nvidiaDriverVariant = "<QUERIED_VARIANT>";
}
```

Where `<QUERIED_VARIANT>` is substituted by the shell variable at write time.

If `query_cached_nvidia_variant` returns nothing (neither stable nor legacy_535 is
cached), abort with a message listing what was checked.

**Step D**: Update the post-install note to show the actual driver version used
(not just "NVIDIA 535 LTS" — it could be any queried version).

### template/etc-nixos-flake.nix changes

Add `++ lib.optional hasKernelOverride kernelOverrideFile` to the five builders
listed above.

---

## Files Modified

- `scripts/install.sh`
- `template/etc-nixos-flake.nix`

---

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| `nix eval` of `inputs.nixpkgs...nvidiaPackages.stable.outPath` fails (e.g., attribute path wrong) | `|| continue` skips to next candidate; final `return 1` falls through to abort |
| `nix path-info --store` network call fails | `&>/dev/null` + `2>&1`; failure = non-zero = continue to next candidate |
| `vexos.gpu.nvidiaDriverVariant` not available in non-desktop roles that still use NVIDIA | Option is declared in `modules/gpu/nvidia.nix` imported by `gpuNvidia` for all NVIDIA variants regardless of role |
| `kernelOverrideFile` in stateless variant conflicts with impermanence | The file is at `/etc/nixos/kernel-install-override.nix`, read by the flake at build time, not at runtime — no conflict |
| Server roles with `hostModule` having `networking.hostId` conflict with override | Override only sets `boot.kernelPackages` + optionally `vexos.gpu.nvidiaDriverVariant` — no hostId interaction |
