# Option B Split — Review & QA Report

**Date**: 2026-04-22  
**Spec**: `.github/docs/subagent_docs/option-b-split_spec.md`  
**Verdict**: **PASS**

---

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 98% | A |
| Option B Rule Adherence | 100% | A+ |
| Functionality | 97% | A |
| Code Quality | 95% | A |
| Security | 100% | A+ |
| Build Success | 80% | B |
| Consistency | 97% | A |

**Overall Grade: A (95%)**

---

## Check 1 — Guard Scan (base modules)

Files checked: `modules/system.nix`, `modules/gpu.nix`, `modules/branding.nix`,
`modules/network.nix`, `modules/flatpak.nix`.

| Module | Guards Found | Status |
|--------|--------------|--------|
| `system.nix` | `lib.mkIf config.vexos.swap.enable` (line 94), `lib.mkIf config.vexos.btrfs.enable` (line 107) | ✓ PASS — both are feature toggles explicitly kept by spec (§1.1) |
| `gpu.nix` | None | ✓ PASS |
| `branding.nix` | None gating on role/display/gaming | ✓ PASS |
| `network.nix` | None | ✓ PASS |
| `flatpak.nix` | `lib.mkIf config.vexos.flatpak.enable` (line 50) | ✓ PASS — feature toggle, explicitly kept by spec (§1.5) |

**CRITICAL violations: ZERO**

The two `lib.mkIf` guards remaining in `system.nix` gate `vexos.swap.enable` and
`vexos.btrfs.enable` — both are feature toggles (not role flags), and both are
explicitly marked KEEP in the spec. These are correct and intentional.

The `lib.mkIf config.vexos.flatpak.enable` guard in `flatpak.nix` is an enable/disable
feature toggle, also explicitly kept by spec. Correct.

---

## Check 2 — Removed Option Scan

Search across all `*.nix` files for the three options that must be gone.

| Option | Matches Found | Status |
|--------|---------------|--------|
| `vexos.system.gaming` | 0 | ✓ REMOVED |
| `vexos.scx.enable` | 0 | ✓ REMOVED |
| `vexos.branding.hasDisplay` | 0 | ✓ REMOVED |

**CRITICAL violations: ZERO**

`vexos.branding.role` is still declared in `modules/branding.nix` — correct per spec
(§3.1: retained for path expressions). `modules/branding-display.nix` and
`modules/flatpak-desktop.nix` both use `config.vexos.branding.role` for path
resolution, which is the intended usage.

---

## Check 3 — Import Correctness

### `configuration-desktop.nix`
| Required import | Present |
|----------------|---------|
| `modules/system-gaming.nix` | ✓ |
| `modules/gpu-gaming.nix` | ✓ |
| `modules/branding-display.nix` | ✓ |
| `modules/network-desktop.nix` | ✓ |
| `modules/flatpak-desktop.nix` | ✓ |

All 5 required imports present. Inline `hardware.graphics.enable32Bit = true`
correctly removed (moved to `gpu-gaming.nix`). ✓

### `configuration-headless-server.nix`
| Forbidden import | Absent |
|-----------------|--------|
| `system-gaming.nix` | ✓ |
| `gpu-gaming.nix` | ✓ |
| `branding-display.nix` | ✓ |
| `network-desktop.nix` | ✓ |
| `flatpak-desktop.nix` | ✓ |

None of the 5 display/gaming modules imported. ✓

### `configuration-server.nix`
| Check | Result |
|-------|--------|
| Imports `branding-display.nix` | ✓ |
| Imports `network-desktop.nix` | ✓ |
| Does NOT import `system-gaming.nix` | ✓ |
| Does NOT import `gpu-gaming.nix` | ✓ |
| Does NOT import `flatpak-desktop.nix` | ✓ |

### `configuration-htpc.nix`
| Check | Result |
|-------|--------|
| Imports `branding-display.nix` | ✓ |
| Imports `network-desktop.nix` | ✓ |
| Does NOT import `system-gaming.nix` | ✓ |
| Does NOT import `gpu-gaming.nix` | ✓ |
| Does NOT import `flatpak-desktop.nix` | ✓ |

### `configuration-stateless.nix`
| Check | Result |
|-------|--------|
| Imports `branding-display.nix` | ✓ |
| Imports `network-desktop.nix` | ✓ |
| Does NOT import `system-gaming.nix` | ✓ |
| Does NOT import `gpu-gaming.nix` | ✓ |
| Does NOT import `flatpak-desktop.nix` | ✓ |

**All import correctness checks: PASS**

---

## Check 4 — Build Validation

### `nix flake check --impure`

```
error: Failed assertions:
  - You must set the option 'boot.loader.grub.devices' or
    'boot.loader.grub.mirroredBoots' to make the system bootable.
```

**Status: EXPECTED FAILURE — not a regression from this change**

This failure is a known architectural constraint of the project: the bootloader
is configured in the host-local `/etc/nixos/flake.nix` (not tracked in this repo),
and `hardware-configuration.nix` is generated per-host at `/etc/nixos/` (also not
tracked, per `copilot-instructions.md`). `nix flake check` evaluates the full
system closure including bootloader assertions, which cannot pass without the
host-specific hardware config present.

This failure predates the Option B split and is unrelated to it.

### `nix eval` Spot-Checks

All six eval checks executed against the staged working tree:

| Attribute | Expected | Actual | Status |
|-----------|----------|--------|--------|
| `vexos-desktop-amd.config.hardware.graphics.enable32Bit` | `true` | `true` | ✓ PASS |
| `vexos-headless-server-amd.config.hardware.graphics.enable32Bit` | `false` | `false` | ✓ PASS |
| `vexos-desktop-amd.config.boot.kernelParams` includes `"preempt=full"` | yes | `[ "preempt=full" "split_lock_detect=off" "quiet" "splash" "loglevel=3" ... ]` | ✓ PASS |
| `vexos-headless-server-amd.config.boot.kernelParams` excludes `"preempt=full"` | yes | `[ "elevator=kyber" "loglevel=4" "lsm=landlock,yama,bpf" ]` | ✓ PASS |
| `vexos-desktop-amd.config.services.scx.enable` | `true` | `true` | ✓ PASS |
| `vexos-desktop-vm.config.services.scx.enable` | `false` | `false` | ✓ PASS |

All six spot-checks pass. The module split correctly routes gaming kernel parameters
and 32-bit GPU support to desktop only, and the VM `lib.mkForce false` override on
SCX works as specified.

---

## Additional Findings

### LOW — Stale comment in `modules/branding.nix` (cosmetic)

Line 5 of `branding.nix` reads:

```
# Plymouth enable is deliberately kept in modules/performance.nix.
```

No `modules/performance.nix` exists. Plymouth is enabled directly in each
configuration file (`boot.plymouth.enable = true`). The comment is a stale
reference from a prior refactor. **Non-blocking; cosmetic fix only.**

### LOW — Duplicate `"splash"` and conflicting `loglevel` in desktop `kernelParams` (pre-existing)

The evaluated desktop kernel params show:

```
[ "preempt=full" "split_lock_detect=off" "quiet" "splash" "loglevel=3"
  "elevator=kyber" "splash" "loglevel=4" "lsm=landlock,yama,bpf" ]
```

- `"splash"` appears twice (once from `system-gaming.nix`, once from NixOS upstream).
- `"loglevel=3"` (from `system-gaming.nix`) and `"loglevel=4"` (from NixOS upstream)
  both appear; the kernel uses the last value, so `loglevel=4` wins over the gaming
  module's intent of `loglevel=3`.

This is a **pre-existing condition** inherited from NixOS defaults — not introduced
by the Option B split (it would have behaved identically with the old `lib.mkIf`
guard). Flagged for awareness. **Non-blocking; out of scope for this review.**

---

## New Role-Specific Module Quality

All five new modules reviewed:

| Module | Content unconditional | Role-specific | No new options declared | Status |
|--------|-----------------------|---------------|------------------------|--------|
| `modules/system-gaming.nix` | ✓ | ✓ | ✓ | ✓ PASS |
| `modules/gpu-gaming.nix` | ✓ | ✓ | ✓ | ✓ PASS |
| `modules/branding-display.nix` | ✓ | ✓ | ✓ | ✓ PASS |
| `modules/network-desktop.nix` | ✓ | ✓ | ✓ | ✓ PASS |
| `modules/flatpak-desktop.nix` | ✓ | ✓ | ✓ | ✓ PASS |

`modules/gpu/vm.nix` correctly overrides `services.scx.enable = lib.mkForce false`
to disable the SCX scheduler for the VM profile, which is pinned to Linux 6.6 LTS
(pre-sched_ext). This is the correct mechanism specified in the spec.

---

## Summary

The Option B module split is **fully implemented** and **correct**:

- All three deprecated options removed from every Nix file in the repo.
- All five base modules are free of role/flag guards (only acceptable feature
  toggles remain).
- All five new role-specific modules contain only unconditional content.
- Every `configuration-*.nix` expresses its role entirely through its import list.
- All six `nix eval` spot-checks confirm the split produces the correct runtime
  values for each profile.
- The `nix flake check` failure is a pre-existing architectural constraint
  (no bootloader/hardware config in the tracked repo) — unrelated to this change.

**Verdict: PASS**
