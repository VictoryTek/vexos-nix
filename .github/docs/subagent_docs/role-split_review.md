# Role-Based Module Split — Review

**Feature**: `role-split`  
**Date**: 2026-04-22  
**Reviewer**: QA Subagent  
**Status**: PASS

---

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 95% | A |
| Best Practices | 95% | A |
| Functionality | 98% | A+ |
| Code Quality | 92% | A- |
| Security | 95% | A |
| Performance | 95% | A |
| Consistency | 90% | A- |
| Build Success | 85% | B |

**Overall Grade: A (93%)**

---

## Build Result

### `nix eval` — all variants PASS

All seven primary configurations evaluate without errors:

| Variant | `nix eval` result |
|---------|-------------------|
| `vexos-desktop-amd` | PASS |
| `vexos-desktop-nvidia` | PASS |
| `vexos-desktop-vm` | PASS |
| `vexos-headless-server-amd` | PASS |
| `vexos-server-amd` | PASS |
| `vexos-htpc-amd` | PASS |
| `vexos-stateless-amd` | PASS |

### `nix flake check --no-build --impure` — FAIL (pre-existing)

Fails with:

```
error: Failed assertions:
- You must set the option 'boot.loader.grub.devices' or
  'boot.loader.grub.mirroredBoots' to make the system bootable.
```

**Root cause**: The `/etc/nixos/hardware-configuration.nix` on this host does not include
bootloader configuration. The bootloader is declared in the host-specific
`/etc/nixos/flake.nix` `bootloaderModule`, which is outside this repository. This
failure is **pre-existing and unrelated to the role-split changes** — it is structural to
the project architecture. The `preflight.sh` script already conditions the `nix flake
check` step on `/etc/nixos/hardware-configuration.nix` being present, and would skip
the check gracefully on machines without it.

### `sudo nixos-rebuild dry-build` — SKIPPED

`sudo` is not available in this environment (`no new privileges` flag is set).
Dry-build validation is deferred to the host machine.

---

## Spec Compliance Details

### 1. New Files

| File | Status | Notes |
|------|--------|-------|
| `modules/packages-common.nix` | ✓ PASS | Exactly matches spec (just, btop, inxi, git, curl, wget) |
| `modules/packages-desktop.nix` | ✓ PASS | Exactly matches spec (brave only) |

### 2. Deleted Files

| File | Status | Notes |
|------|--------|-------|
| `modules/packages.nix` | ✓ PASS | Deleted; confirmed absent via file search |

### 3. Module Changes

#### `modules/system.nix`

| Change | Status | Notes |
|--------|--------|-------|
| `vexos.system.gaming` option declared | ✓ PASS | Correct `lib.mkOption`, type `bool`, default `false` |
| Gaming kernel params gated | ✓ PASS | `preempt=full`, `split_lock_detect=off`, `quiet`, `splash`, `loglevel=3` in `lib.mkIf config.vexos.system.gaming` |
| `vm.max_map_count = 2147483642` gated | ✓ PASS | Confirmed: desktop=2147483642, headless=kernel default (1048576) |
| THP madvise rules gated | ✓ PASS | Inside gaming `mkIf` block |
| `boot.plymouth.enable = lib.mkDefault false` | ✓ PASS | Display roles override to `true` in their configs |
| SCX service gated | ✓ PASS | `lib.mkIf (gaming && scx.enable)` — headless `services.scx.enable` evaluates to `false` |
| `elevator=kyber` unconditional | ✓ PASS | Remains in unconditional `boot.kernelParams` |

> **NOTE**: The spec states the `vexos.scx.enable` option declaration should move inside the
> gaming gate. In NixOS module system, `options` declarations cannot be placed inside
> `lib.mkIf` — they must be at the top level. The implementation correctly keeps the option
> declaration unconditional but gates the `services.scx` config block behind
> `(gaming && scx.enable)`. This achieves the identical functional outcome and is the correct
> NixOS approach.

#### `modules/gpu.nix`

| Change | Status | Notes |
|--------|--------|-------|
| `enable32Bit = lib.mkDefault false` | ✓ PASS | Desktop overrides to `true`; headless correctly `false` |
| `extraPackages32` gated behind `enable32Bit` | ✓ PASS | `lib.mkIf config.hardware.graphics.enable32Bit` |
| `vulkan-tools`, `mesa-demos` gated behind gaming | ✓ PASS | Via `lib.optionals config.vexos.system.gaming` |
| `vulkan-loader` remains unconditional | ✓ PASS | Correct: runtime dep, not diagnostic |

#### `modules/branding.nix`

| Change | Status | Notes |
|--------|--------|-------|
| `vexos.branding.hasDisplay` option declared | ✓ PASS | `lib.mkOption`, type `bool`, default `true` |
| `vexosWallpapers` gated behind `hasDisplay` | ✓ PASS | Via `lib.optionals config.vexos.branding.hasDisplay` |
| `environment.etc."vexos/gdm-logo.png"` gated | ✓ PASS | `lib.mkIf config.vexos.branding.hasDisplay` |
| `programs.dconf.profiles.gdm` gated | ✓ PASS | `lib.mkIf config.vexos.branding.hasDisplay` |
| Plymouth theme/logo unconditional | ✓ PASS | Harmless when Plymouth is disabled |

#### `modules/flatpak.nix`

| Change | Status | Notes |
|--------|--------|-------|
| `desktopOnlyApps` list extracted | ✓ PASS | 6 gaming/dev apps correctly extracted |
| `defaultApps` reduced to 12 entries | ✓ PASS | No gaming/dev apps in universal list |
| `desktopOnlyApps` added via `lib.optionals (role == "desktop")` | ✓ PASS | Correct conditional |
| Server/HTPC `excludeApps` reduced to GIMP only | ✓ PASS | Confirmed via `nix eval` |

#### `modules/network.nix`

| Change | Status | Notes |
|--------|--------|-------|
| `samba` gated behind `hasDisplay` | ✓ PASS | `lib.optionals config.vexos.branding.hasDisplay` |
| `cifs-utils` remains unconditional | ✓ PASS | SMB mount client useful everywhere |

### 4. Configuration File Changes

| File | Import correctness | Options set | Status |
|------|--------------------|-------------|--------|
| `configuration-desktop.nix` | `packages-common.nix` + `packages-desktop.nix` ✓ | `vexos.system.gaming=true`, `boot.plymouth.enable=true`, `hardware.graphics.enable32Bit=true` ✓ | PASS |
| `configuration-headless-server.nix` | `packages-common.nix` only ✓ | `vexos.branding.hasDisplay=false` ✓; no `lib.mkForce` overrides ✓ | PASS |
| `configuration-server.nix` | `packages-common.nix` + `packages-desktop.nix` ✓ | `boot.plymouth.enable=true` ✓; `excludeApps=[GIMP]` ✓ | PASS |
| `configuration-htpc.nix` | `packages-common.nix` + `packages-desktop.nix` ✓ | `boot.plymouth.enable=true` ✓; `excludeApps=[GIMP]` ✓ | PASS |
| `configuration-stateless.nix` | `packages-common.nix` + `packages-desktop.nix` ✓ | `boot.plymouth.enable=true` ✓; `excludeApps=[GIMP]` ✓ | PASS |

### 5. Unchanged Files

Verified spec-listed unchanged files are indeed unchanged (gnome.nix, gaming.nix, audio.nix, development.nix, virtualization.nix, impermanence.nix, gpu/{amd,nvidia,intel,vm}.nix, flake.nix).

---

## Runtime Verification (via `nix eval`)

All assertions confirmed via direct attribute evaluation:

```
vexos.system.gaming:
  desktop-amd  → true   ✓
  headless-amd → false  ✓

hardware.graphics.enable32Bit:
  desktop-amd  → true   ✓
  headless-amd → false  ✓

vexos.branding.hasDisplay:
  headless-server-amd → false  ✓
  server-amd          → true   ✓
  htpc-amd            → true   ✓
  stateless-amd       → true   ✓

boot.plymouth.enable:
  desktop-amd         → true   ✓
  headless-server-amd → false  ✓
  server-amd          → true   ✓

services.scx.enable:
  desktop-amd         → true   ✓
  headless-server-amd → false  ✓

boot.kernel.sysctl."vm.max_map_count":
  desktop-amd         → 2147483642  ✓ (gaming value)
  headless-server-amd → 1048576     ✓ (kernel default; gaming param absent)

Packages absent from headless-server-amd:
  brave, samba, vulkan-tools, mesa-demos, vexos-wallpapers → all ABSENT ✓

system.stateVersion:
  All five role configs → "25.11"  ✓ (unchanged)

hardware-configuration.nix tracked in git: NO ✓

vexos.branding.role:
  desktop-amd         → "desktop"   ✓
  headless-server-amd → "server"    ✓
  server-amd          → "server"    ✓
  htpc-amd            → "htpc"      ✓
  stateless-amd       → "stateless" ✓
```

---

## Findings

### CRITICAL

None.

---

### WARNING

**W1 — Stale `packages.nix` comment references in home-*.nix files**

10 occurrences across 4 files reference the now-deleted `modules/packages.nix`:

- `home-desktop.nix` lines 36, 41, 44
- `home-server.nix` lines 25, 30, 32
- `home-headless-server.nix` lines 19, 23
- `home-stateless.nix` lines 29, 34, 36

These are documentation comments only — not import statements — and do not affect
evaluation or builds. However, they will mislead any developer reading those files.
The comments should be updated to reference `packages-common.nix` (for `just`, `btop`,
`inxi`, `git`, `curl`, `wget`) and `packages-desktop.nix` (for `brave`).

---

### INFO

**I1 — Duplicate `splash` and conflicting `loglevel` values in desktop kernel params**

Evaluated desktop kernel params include both `"loglevel=3"` (from gaming params) and
`"loglevel=4"` (from the host's `/etc/nixos/hardware-configuration.nix`), plus `"splash"`
appearing twice. The kernel uses the last value, so `loglevel=4` wins over the intended
`loglevel=3`. This is not caused by the role-split change; it is an interaction with the
host hardware configuration. Low priority.

**I2 — `vexos.scx.enable` option declared unconditionally (correct NixOS behaviour)**

The spec states the scx option declaration should move inside the gaming gate. This is not
possible in the NixOS module system (`options` must be top-level). The implementation's
approach — declaring the option unconditionally and gating the service behind
`(gaming && scx.enable)` — achieves the identical runtime outcome and is the canonical
NixOS pattern. No change required.

**I3 — `nix flake check` pre-existing failure**

`nix flake check` fails on this machine because `/etc/nixos/hardware-configuration.nix`
does not include bootloader configuration (that lives in the host-local
`/etc/nixos/flake.nix`). This is structural to the project architecture and is handled
by `scripts/preflight.sh` which skips the check when hardware-config does not have a
full system configuration. Not caused by role-split.

---

## Verdict

**PASS**

All critical spec items are implemented correctly. All seven configuration variants evaluate
without errors. Package gating, option flags, and import changes all behave as specified.
The two WARNING items (stale comments in home files and a pre-existing flake check
infrastructure limitation) do not require blocking refinement — they are cosmetic or
pre-existing. The CRITICAL count is zero.
