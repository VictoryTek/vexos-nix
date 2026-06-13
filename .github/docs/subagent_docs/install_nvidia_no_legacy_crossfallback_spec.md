# Spec: Do not cross-branch fall back to legacy_535 when role is "latest"

## Problem

`query_cached_nvidia_variant()` iterates `stable → legacy_535` and returns the first
variant whose driver outPath is present in cache.nixos.org. This is called only when
`NVIDIA_SUFFIX=""` (user selected the "latest" driver branch, e.g. RTX 20xx+). If
`stable` (580.x) is uncached, the function currently falls through to check `legacy_535`
(535.x) and, if that IS cached, returns `"legacy_535"`.

This is wrong. `legacy_535` does not support GPUs that require the "latest" driver line
(e.g. RTX 40-series). Installing it produces a non-functional GPU — worse than aborting.
The user's driver branch selection must be respected.

The call site guard (`NVIDIA_SUFFIX = ""`) already ensures this code path is only entered
for "latest" builds, so querying `legacy_535` here is always incorrect.

## Fix

Remove `legacy_535` from the query loop. When `NVIDIA_SUFFIX=""`, only check `stable`.
If `stable` is uncached, emit the source-build-or-abort prompt as before — no
cross-branch fallback.

### Changes — `scripts/install.sh`

1. **Function comment** (line 409): remove mention of `legacy_535`.

2. **Loop** (line 413): change
   ```bash
   for nv_attr in stable legacy_535; do
   ```
   to
   ```bash
   for nv_attr in stable; do
   ```

3. **`case` inside the loop** (lines 422-425): remove the now-unreachable `legacy_535`
   arm; keep only `stable → echo "latest"`.

4. **"Checked:" message** (line 515): change
   ```
   echo -e "  Checked: stable (580.x), legacy_535 (535.x)"
   ```
   to
   ```
   echo -e "  Checked: stable (580.x)"
   ```

## Non-Goals

- No change to the `NVIDIA_SUFFIX="-legacy535"` code path (separate path, not reached
  by this function).
- No change to how legacy_535 installs are handled.
- No new attributes (production, beta, etc.) — keep it minimal.

## Files Modified

- `scripts/install.sh`
