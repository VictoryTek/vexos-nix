# Spec: Fix query_cached_nvidia_variant silent exit under set -euo pipefail

## Problem

`install.sh` runs with `set -euo pipefail`. When `query_cached_nvidia_variant` finds
no cached NVIDIA variant it executes `return 1`. The call site:

```bash
CACHED_NV_VARIANT=$(query_cached_nvidia_variant "linuxPackages")
```

Under `set -e`, a command substitution that exits non-zero immediately aborts the
script — the subsequent `if [ -z "$CACHED_NV_VARIANT" ]` block is never reached,
producing a silent exit with no user-visible message.

## Fix

Change `query_cached_nvidia_variant` to always `return 0`. Signal "nothing found"
via empty stdout (caller already checks `[ -z "$CACHED_NV_VARIANT" ]`).

Replace `return 1` at the end of the function with:
```bash
  # No cached variant found — print nothing, return 0.
  # Caller checks for empty output; return 1 would silently abort under set -e.
  return 0
```

## Files Modified

- `scripts/install.sh`
