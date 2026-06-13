# Spec: NVIDIA cache fallback — roll back nixpkgs to most recent cached driver

## Problem

The current fallback only checks whether the CURRENT nixpkgs pin's stable driver is in
cache. If it isn't, it prompts the user. But within a single nixpkgs pin there is only
one stable driver version — there is no way to "find the previous version" without
looking at an older nixpkgs commit.

What the user wants:
> "stable 580.142 is not cached → find the most recent nixpkgs commit where stable
> WAS cached (e.g. 580.140) → temporarily use that nixpkgs pin → install silently"

## Solution

Replace `query_cached_nvidia_variant()` with `find_cached_nixpkgs_for_nvidia()` that:

1. Reads the current nixpkgs rev from `/etc/nixos/flake.lock` via `jq`
2. Calls the GitHub API to get the 5 most recent commits that touched
   `pkgs/os-specific/linux/nvidia-x11/default.nix`, starting from the current rev
3. For each commit rev, evaluates `linuxPackages.nvidiaPackages.stable.outPath` by
   importing that nixpkgs revision via `builtins.fetchTarball` (impure, no sha256 needed
   under `--impure` eval) with `allowUnfree = true`
4. Checks if the out_path is in `cache.nixos.org` via `nix path-info --store`
5. Returns the first nixpkgs rev where stable is cached, or empty if none found

When a cached rev is found:
- Save current flake.lock contents for rollback
- Run `nix flake lock /etc/nixos --override-input nixpkgs github:NixOS/nixpkgs/<REV>`
  to pin nixpkgs in flake.lock to the found rev
- Track updated flake.lock with git
- The kernel-install-override.nix already written (`boot.kernelPackages = linuxPackages`)
  remains unchanged — with the older nixpkgs, `nvidiaPackages.stable` resolves to the
  cached version automatically; no `nvidiaDriverVariant` override needed
- Run dry-build to verify → REMAINING2
- If REMAINING2 empty → proceed with install, print success message
- If REMAINING2 non-empty → restore flake.lock from backup, remove kernel-install-override.nix,
  fall through to source-build prompt

When no cached rev found in history (true last-resort case):
- Offer source-build-or-abort prompt as before

## Why nixpkgs rollback instead of a driver pin overlay

An overlay would require knowing the store path hash of the older driver before NixOS
evaluation, which is circular. Rolling back nixpkgs is clean: `nvidiaPackages.stable`
from the older nixpkgs resolves to the cached version by construction. The `just update`
the user runs after first boot restores nixpkgs to the latest pin automatically.

## User-visible flow (normal case)

```
⚠ NVIDIA driver packages are not yet in the binary cache.

Searching nixpkgs history for the most recent cached NVIDIA driver...

✓ Found cached NVIDIA driver at nixpkgs a1b2c3d4 (2026-06-10).
Temporarily using this nixpkgs pin for first install.
The latest version will be applied automatically when you run 'just update'
or use the Up app, once cache.nixos.org has built it (typically 1-3 days).

Verifying fallback kernel + cached NVIDIA resolves all cache misses...
✓ All packages available in binary cache.
```

No user prompt — fully automatic.

## Files Modified

- `scripts/install.sh`

## Constraints

- `nix eval --impure` is already used throughout — `builtins.fetchTarball` without sha256
  is valid under `--impure`
- GitHub API for public NixOS/nixpkgs requires no authentication for 60 req/hour
- `jq` is already required by the installer (checked at startup)
- `curl` is already used by the installer (it's how install.sh is delivered)
- Per-rev nixpkgs tarball download: ~90MB per rev from GitHub archive CDN; acceptable
  for an installer; Nix caches tarballs in the store so subsequent evals of the same rev
  are instant
- `nix flake lock --override-input` requires `nix-command flakes` experimental features
  — already used throughout
