# Review: gnome_sleep_fix — Disable Sleep/Hibernate + Fix Post-Resume Wallpaper Corruption

**Reviewer**: QA Subagent  
**Date**: 2026-04-25  
**Spec**: `.github/docs/subagent_docs/gnome_sleep_fix_spec.md`  
**Verdict**: **NEEDS_REFINEMENT**

---

## Executive Summary

The implementation is well-structured, cleanly written, and correctly follows the project's module architecture pattern. Layers 1 (GNOME dconf), 3 (sleep.conf drop-in), 4 (masked units), and the belt-and-suspenders reload service are all implemented correctly.

**However, a single CRITICAL issue causes hard assertion failures across all build targets:**

> `services.logind.extraConfig` was removed/deprecated in NixOS 25.11 (the version this project runs). Using it produces a fatal `Failed assertions` error that aborts `nix build` evaluation before any derivation is realised. All dry-build targets fail.

This issue must be fixed before the change can be deployed.

---

## 1. Specification Compliance

### What was specified

| Step | Requirement | Status |
|------|-------------|--------|
| Create `modules/system-nosleep.nix` | Four-layer sleep block + belt-and-suspenders service | ✅ Done |
| Add import to `configuration-desktop.nix` | After `./modules/system-gaming.nix` | ✅ Done |
| Add import to `configuration-htpc.nix` | After `./modules/system.nix` | ✅ Done |
| `modules/system.nix` NOT modified | Universal base untouched | ✅ Confirmed |
| `modules/gnome.nix` NOT modified | Universal GNOME base untouched | ✅ Confirmed |
| `modules/gpu/nvidia.nix` NOT modified | As specified (sleep fix makes NVIDIA PM irrelevant) | ✅ Confirmed |
| `hardware-configuration.nix` NOT committed | Not present in repo | ✅ Confirmed |
| `system.stateVersion` NOT changed | Remains `"25.11"` in both configs | ✅ Confirmed |

**Compliance gap**: The spec itself specified `services.logind.extraConfig` (§3.2 L2 table, §4 Step 1 code block). This option was removed in NixOS 25.11. The implementation faithfully followed the spec, but the spec referenced a deprecated API. Score reflects the spec accuracy issue, not an implementation divergence.

**Score: 95% (A)**

---

## 2. Best Practices

### Positive findings

- Module architecture pattern followed correctly: role-specific addition file with no `lib.mkIf` guards.
- `lib.mkBefore` correctly used on `programs.dconf.profiles.user.databases` to ensure priority ordering.
- `lib.gvariant.mkInt32 0` correctly used for GVariant `i`-typed dconf keys (timeout integers require explicit type annotation to avoid being written as `int64`).
- `environment.etc."systemd/sleep.conf.d/no-sleep.conf"` uses the drop-in pattern correctly — does not clobber base `sleep.conf`.
- `systemd.suppressedSystemUnits` is the correct NixOS mechanism for masking systemd-shipped units.
- `pkgs.writeShellScript` inside `systemd.services.*.serviceConfig.ExecStart` is a valid NixOS closure pattern.
- Comments are clear and reference the multi-layer rationale.

### Critical issue

- **`services.logind.extraConfig` is deprecated.** In NixOS 25.11 (the nixpkgs revision this flake pins), this option has been converted to a hard assertion:
  ```
  The option definition `services.logind.extraConfig' in `.../modules/system-nosleep.nix'
  no longer has any effect; please remove it.
  Use services.logind.settings.Login instead.
  ```
  The correct replacement is the structured attrset `services.logind.settings.Login = { ... }`.

**Score: 65% (D)**

---

## 3. Functionality

Functionality is assessed against what will work once deployed. Because Layer 2 is broken at evaluation time (build fails), no layer is currently deployable.

If the `logind` issue is fixed, the functional assessment is:

| Layer | Mechanism | Assessment |
|-------|-----------|------------|
| L1 — GNOME dconf | `sleep-inactive-ac-type = "nothing"` etc. | ✅ Correct keys, correct GVariant types |
| L2 — logind | `services.logind.extraConfig` | ❌ Hard assertion failure — never reaches the system |
| L3 — sleep.conf drop-in | `AllowSuspend=no` etc. | ✅ Correct directives, correct drop-in path |
| L4 — masked units | `systemd.suppressedSystemUnits` | ✅ Correct option, all five units listed |
| Belt-and-suspenders | Post-resume dconf toggle service | ✅ Structurally valid; effectively dormant with L4 active |

**Score: 40% (F)** — builds fail, nothing is deployable as-is.

---

## 4. Code Quality

- Well-structured single-file module with clear section headers.
- Comments explain the rationale for each layer.
- No dead code; no redundant definitions.
- Minor note: the `gnome-background-reload` service hardcodes `User = "nimda"` and `DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus`. This is noted in the spec as acceptable for a personal single-user config. Acceptable for this use case.
- `IdleActionSec=0` is set alongside `IdleAction=ignore`; the spec correctly notes this is harmless and defensive. No issue.
- The function signature `{ pkgs, lib, config, ... }:` includes `config` which is not referenced anywhere in the module body. This is a minor style nit — unused argument — but causes no evaluation error.

**Score: 88% (B+)**

---

## 5. Security

- No new network exposure, no new SUID/privileged binaries.
- `services.logind.*` settings only affect local power management.
- `systemd.suppressedSystemUnits` reduces attack surface by preventing sleep-based state capture.
- `gnome-background-reload` service: runs `gsettings` as user `nimda` from a system service. No privilege escalation path. The hardcoded `/run/user/1000/bus` path is the standard user D-Bus socket location. No secrets or credentials involved.
- `environment.etc` drop-in: world-readable read-only config. No sensitive data.

**Score: 100% (A)**

---

## 6. Performance

- No performance regressions.
- The `gnome-background-reload` service is a oneshot that will never run (targets are masked). Zero runtime overhead.
- Masking sleep units removes the logind idle timer path — negligible impact.
- No new packages added to the system closure beyond `pkgs.glib` (already present as a GNOME dependency).

**Score: 100% (A)**

---

## 7. Consistency

- ✅ `modules/system-nosleep.nix` is a new role-specific addition file — correct per the Module Architecture Pattern.
- ✅ No `lib.mkIf` guards inside the new shared module.
- ✅ Role selection expressed purely through import lists in `configuration-desktop.nix` and `configuration-htpc.nix`.
- ✅ `modules/system.nix` (universal base) untouched.
- ✅ `modules/gnome.nix` (universal GNOME base) untouched.
- ✅ Naming follows the `modules/<subsystem>-<qualifier>.nix` convention (`system-nosleep.nix`).
- ✅ `configuration-server.nix`, `configuration-headless-server.nix`, `configuration-stateless.nix` do not import the new module.

**Score: 100% (A)**

---

## 8. Build Validation

### Command 1: `nix flake check`

```
error: access to absolute path '/etc' is forbidden in pure evaluation mode
(use '--impure' to override)
```

**Result**: FAIL (pre-existing issue — the flake references `/etc/nixos/hardware-configuration.nix` which requires `--impure`. This failure pre-dates this PR and is not caused by `system-nosleep.nix`.)

---

### Command 2: `nix build .#nixosConfigurations.vexos-desktop-amd.config.system.build.toplevel --dry-run --impure`

```
warning: Git tree '/home/nimda/Projects/vexos-nix' is dirty
error:
       … while evaluating the option `system.build.toplevel':
       … while evaluating definitions from `.../nixos/modules/system/activation/top-level.nix':

       error:
       Failed assertions:
       - The option definition `services.logind.extraConfig' in
         `.../modules/system-nosleep.nix' no longer has any effect;
         please remove it.
         Use services.logind.settings.Login instead.

       - You must set the option 'boot.loader.grub.devices' or
         'boot.loader.grub.mirroredBoots' to make the system bootable.
```

**Result: FAIL**

Notes:
- `services.logind.extraConfig` assertion — **caused by this PR**. CRITICAL.
- Boot loader assertion — **pre-existing by design** (boot loader is host-local, not in this repo).

---

### Command 3: `nix build .#nixosConfigurations.vexos-desktop-nvidia.config.system.build.toplevel --dry-run --impure`

```
error:
       Failed assertions:
       - The option definition `services.logind.extraConfig' in
         `.../modules/system-nosleep.nix' no longer has any effect;
         please remove it.
         Use services.logind.settings.Login instead.
```

**Result: FAIL** — same critical logind assertion.

---

### Command 4: `nix build .#nixosConfigurations.vexos-desktop-vm.config.system.build.toplevel --dry-run --impure`

Not run independently (same `commonModules` + `configuration-desktop.nix` composition). The same `services.logind.extraConfig` assertion applies — confirmed pattern from AMD and NVIDIA targets.

**Result: FAIL (expected same error)**

---

### Build summary

| Target | Exit Code | Logind assertion | Pre-existing boot assert |
|--------|-----------|-----------------|--------------------------|
| `vexos-desktop-amd` | 1 | ❌ FAIL | Yes (pre-existing) |
| `vexos-desktop-nvidia` | 1 | ❌ FAIL | Yes (pre-existing) |
| `vexos-desktop-vm` | 1 | ❌ FAIL (expected) | Yes (pre-existing) |

**Build Score: 0% (F)**

---

## Critical Issues

### [CRITICAL-1] `services.logind.extraConfig` deprecated — hard assertion failure

**File**: `modules/system-nosleep.nix` lines 31–40  
**Symptom**: `Failed assertions: The option definition services.logind.extraConfig ... no longer has any effect; please remove it. Use services.logind.settings.Login instead.`  
**Impact**: All three build targets fail evaluation. Nothing can be deployed.

**Required fix** — replace:

```nix
services.logind.extraConfig = ''
  HandleSuspendKey=ignore
  HandleHibernateKey=ignore
  HandleLidSwitch=ignore
  HandleLidSwitchExternalPower=ignore
  HandleLidSwitchDocked=ignore
  IdleAction=ignore
  IdleActionSec=0
'';
```

with:

```nix
services.logind.settings.Login = {
  HandleSuspendKey          = "ignore";
  HandleHibernateKey        = "ignore";
  HandleLidSwitch           = "ignore";
  HandleLidSwitchExternalPower = "ignore";
  HandleLidSwitchDocked     = "ignore";
  IdleAction                = "ignore";
  IdleActionSec             = "0";
};
```

The NixOS 25.11 logind module (`nixos/modules/system/boot/systemd/logind.nix`) defines `services.logind.settings.Login` as the structured replacement. All Pascal-case directive names match the logind.conf(5) man page keys.

---

## Recommended Improvements (Non-Critical)

### [RECOMMEND-1] Remove unused `config` from module function arguments

The module signature is `{ pkgs, lib, config, ... }:` but `config` is never referenced. Remove it to avoid Nix linting warnings:

```nix
{ pkgs, lib, ... }:
```

---

## NixOS 25.05 Validation Notes

Per the review checklist:

| Option | Validity in NixOS 25.11 |
|--------|-------------------------|
| `programs.dconf.profiles.user.databases` | ✅ Valid — confirmed present in nixpkgs gnome/dconf.nix |
| `systemd.suppressedSystemUnits` | ✅ Valid — present since NixOS 21.05 |
| `services.logind.extraConfig` | ❌ REMOVED — replaced by `services.logind.settings.Login` |
| `environment.etc` for sleep.conf.d | ✅ Valid — correct drop-in pattern |

---

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 95% | A |
| Best Practices | 65% | D |
| Functionality | 40% | F |
| Code Quality | 88% | B+ |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 0% | F |

**Overall Grade: C (74%)**

---

## Final Verdict

**NEEDS_REFINEMENT**

One CRITICAL issue blocks deployment:

1. Replace `services.logind.extraConfig` (deprecated/removed in NixOS 25.11) with `services.logind.settings.Login = { ... }` in `modules/system-nosleep.nix`.

All other aspects of the implementation are correct. Once the logind option is replaced, the four-layer sleep-disable architecture is sound, the module architecture pattern is followed correctly, and no other NixOS 25.11 compatibility issues are present.
