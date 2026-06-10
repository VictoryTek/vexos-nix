# Spec: Install-Time Kernel Fallback

**Feature name:** `install_kernel_fallback`
**Date:** 2026-06-09
**Scope:** `scripts/install.sh`, `template/etc-nixos-flake.nix`, `modules/nix.nix`

---

## 1. Current State Analysis

### Kernel layout
| Role | Module | Kernel |
|---|---|---|
| desktop | `modules/system-desktop-kernel.nix` | `linuxPackages_6_18` (pinned, non-default) |
| stateless | `modules/system-lts-kernel.nix` | `linuxPackages_6_12` (LTS, always cached) |
| htpc | `modules/system-lts-kernel.nix` | `linuxPackages_6_12` (LTS, always cached) |
| server / headless-server | `modules/system-lts-kernel.nix` | `linuxPackages_6_12` (LTS, always cached) |
| vanilla | `system.nix` mkDefault | `linuxPackages_latest` (default, well cached) |

### Install script cache-check behavior (current)
`install.sh` runs `nixos-rebuild dry-build`, extracts "will be built" derivations, filters them through a
`grep -E -- '-[0-9]+\.[0-9]+'` pattern, and **aborts** (`exit 1`) if any remain after filtering out known
system-assembly derivations. The user is instructed to retry in 24 hours.

### vexos-update heavy-build engine (current)
`modules/nix.nix` installs `vexos-update` which uses `HEAVY_BUILD_REGEX`:
```
'^(linux-[0-9][^/]*-modules|linux-[0-9][^/]*-modules-shrunk|NVIDIA-Linux-|nvidia-x11-|nvidia-settings-|openrazer-[0-9])'
```
If any dry-build output matches this regex, it restores `flake.lock` and exits 2 (VEXOS_CACHE_BLOCK).

### Problem
When `desktop-nvidia` is installed and the kernel (`6.18.x`) is newer than the Hydra build cache
for `nvidia-x11`, `nvidia-settings`, and `openrazer`, the install script aborts. The user cannot
install at all until cache.nixos.org catches up (24-72 hours). The packages that cause the abort
are exclusively kernel-dependent — switching to the channel-default kernel (`linuxPackages`,
currently 6.12 on nixos-25.11) would make all packages available from cache immediately.

---

## 2. Problem Definition

The abort guard in the install script is correct for **non-kernel packages** (e.g., a missing
Rust crate or Electron app that would take hours). It is **too conservative** for kernel-dependent
packages because the exact same driver/module is available in cache for the channel-default
kernel. The user ends up blocked on hardware they own and ready to use.

**Goal:** When the only cache misses on first install are kernel-dependent packages, automatically
fall back to `linuxPackages` (channel default) for the initial installation, then let
`vexos-update` upgrade the kernel transparently once the target-kernel packages are cached.

**Scope constraint:** Only the `desktop` role currently uses a non-default kernel (`linuxPackages_6_18`).
All other roles use LTS or channel-default kernels that are always cached. The override mechanism
is added only to `mkVariant` (desktop builder) in the template flake.

---

## 3. Proposed Solution Architecture

### 3.1 Override file: `/etc/nixos/kernel-install-override.nix`

A NixOS module written by the install script at `/etc/nixos/` when kernel-dep fallback triggers:

```nix
# Written by vexos-nix installer — fallback to channel-default kernel.
# Removed automatically by vexos-update once target kernel packages are cached.
# To upgrade manually: delete this file, then run: just update
{ lib, pkgs, ... }:
{
  boot.kernelPackages = lib.mkForce pkgs.linuxPackages;
}
```

`lib.mkForce` is required because `system-desktop-kernel.nix` sets `boot.kernelPackages` at
priority 100 (no mkDefault), so a plain assignment would conflict.

### 3.2 Template flake: optional include in `mkVariant`

Pattern identical to the existing `server-services.nix` opt-in:

```nix
kernelOverrideFile = ./kernel-install-override.nix;
hasKernelOverride  = builtins.pathExists kernelOverrideFile;
```

In `mkVariant` module list, append:
```nix
++ lib.optional hasKernelOverride kernelOverrideFile
```

When the file does not exist (normal case), `pathExists` returns false and the list is
unchanged. When it exists (post-fallback install), it is included and overrides the kernel.

`mkStatelessVariant` and `mkHtpcVariant` are **not** modified — their roles always use LTS
kernels that are fully cached.

### 3.3 Install script: kernel-dep-only detection and fallback

After the existing `SOURCE_BUILDS` filter runs, classify the cache misses:

```bash
HEAVY_BUILD_REGEX='^(linux-[0-9][^/]*-modules|NVIDIA-Linux-|nvidia-x11-|nvidia-settings-|openrazer-[0-9])'
NON_HEAVY_BUILDS=$(printf '%s\n' "$SOURCE_BUILDS" | grep -Ev "$HEAVY_BUILD_REGEX" || true)
```

If `SOURCE_BUILDS` is non-empty **and** `NON_HEAVY_BUILDS` is empty → all misses are
kernel-dep → trigger fallback:

1. Write `/etc/nixos/kernel-install-override.nix`
2. Print a yellow notice explaining the fallback
3. Re-run `dry-build` to confirm the override resolves all cache misses
4. If the re-run still has source builds → restore abort behavior (non-kernel issue)
5. If re-run passes → proceed with `nixos-rebuild switch/boot`
6. After successful install, print a notice that `just update` will upgrade the kernel

If `SOURCE_BUILDS` is non-empty **and** `NON_HEAVY_BUILDS` is also non-empty → original abort
behavior unchanged (non-kernel packages are missing → can't help with a kernel switch).

### 3.4 vexos-update: auto-clear override when target kernel is cached

At the start of `vexos-update`, before updating flake inputs, check for the override file:

```bash
OVERRIDE_FILE="/etc/nixos/kernel-install-override.nix"
if [ -f "$OVERRIDE_FILE" ]; then
  echo "Kernel install override detected — checking if target kernel is now cached..."
  rm "$OVERRIDE_FILE"
  DRY_CHECK=$(nixos-rebuild dry-build --flake path:/etc/nixos#"$VARIANT" 2>&1 || true)
  STILL_HEAVY=$(printf '%s\n' "$DRY_CHECK" \
    | awk '/will be built:/{p=1;next} /will be fetched:|^building |^[^ \t]/{p=0} p && /\/nix\/store\//{sub(/.*\/nix\/store\/[a-z0-9]+-/,""); print}' \
    | grep -E "$HEAVY_BUILD_REGEX" || true)
  if [ -n "$STILL_HEAVY" ]; then
    # Target kernel not yet in cache — restore override and continue with fallback kernel
    cat > "$OVERRIDE_FILE" << 'NIXEOF'
# Written by vexos-nix installer — fallback to channel-default kernel.
# Removed automatically by vexos-update once target kernel packages are cached.
# To upgrade manually: delete this file, then run: just update
{ lib, pkgs, ... }:
{
  boot.kernelPackages = lib.mkForce pkgs.linuxPackages;
}
NIXEOF
    echo "Target kernel packages not yet cached — keeping channel-default kernel."
    echo "Run 'just update' again in 1-3 days to upgrade automatically."
  else
    echo "Target kernel packages are cached — override removed. Kernel will upgrade on this update."
  fi
fi
```

This check happens **before** `flake update` so it uses the current pinned revision.
If the check passes (override removed), the rest of `vexos-update` proceeds normally
with the target kernel included. If the check fails (override restored), the remainder
of `vexos-update` runs with the override still in place — the heavy-build block engine
then handles the update as normal.

---

## 4. Implementation Steps

1. **`template/etc-nixos-flake.nix`** — add `kernelOverrideFile` / `hasKernelOverride` to the
   `let` block; append `lib.optional hasKernelOverride kernelOverrideFile` to `mkVariant`
   module list only.

2. **`scripts/install.sh`** — after `SOURCE_BUILDS` is computed, add kernel-dep classification
   block:
   - Classify into `NON_HEAVY_BUILDS` using the same `HEAVY_BUILD_REGEX` as `vexos-update`
   - If kernel-dep-only: write override file, re-run dry-build to confirm, continue
   - If mixed: abort as before
   - Print clear user-facing messages at each branch

3. **`modules/nix.nix`** — prepend the override-check block to `vexos-update` before the
   `flake update` call.

---

## 5. Dependencies

No new flake inputs or external libraries. All changes are pure bash and Nix.

Context7 not required — no external APIs or versioned libraries involved.

---

## 6. Risks and Mitigations

| Risk | Mitigation |
|---|---|
| Very new hardware requiring 6.18+ kernel for basic function (new AMD iGPU, etc.) | Install script prints a warning before switching to fallback kernel: "If your hardware requires Linux 6.18+, run the installer again and choose to build from source." |
| Override file left behind if user manually deletes it and forgets to rebuild | File is self-documenting with removal instructions in comments; `vexos-update` cleans it automatically |
| Re-run dry-build after writing override fails (bad network, etc.) | Abort with error; remove override file so state is clean; original abort message shown |
| `lib.mkForce` on `boot.kernelPackages` conflicting with other modules | No other module sets `boot.kernelPackages` with mkForce in the desktop stack; conflict impossible |
| Override file present in CI evaluation | CI stubs `/etc/nixos/` at evaluation time; `builtins.pathExists ./kernel-install-override.nix` returns false; CI unaffected |
