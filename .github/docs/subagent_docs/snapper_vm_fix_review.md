# Review: snapper_vm_fix — Disable btrfs/Snapper on VM Host

**Feature:** `snapper_vm_fix`  
**Reviewer:** NixOS Configuration Review Agent  
**Date:** 2026-04-09  
**Status:** PASS  

> **Note:** This review supersedes the 2026-04-06 review. The implementation was
> updated from `lib.mkForce` individual-service overrides to the cleaner
> `vexos.btrfs.enable = false` approach (spec §4.1, preferred). This document
> reflects the current code state.  

---

## 1. Files Reviewed

| File | Purpose |
|------|---------|
| `.github/docs/subagent_docs/snapper_vm_fix_spec.md` | Specification |
| `hosts/vm.nix` | Modified implementation |
| `modules/system.nix` | Context — `vexos.btrfs.enable` option declaration and btrfs block |
| `hosts/amd.nix` | Verified unaffected |
| `hosts/nvidia.nix` | Verified unaffected |
| `hosts/intel.nix` | Verified unaffected |
| `flake.nix` | Context — flake inputs |
| `configuration.nix` | Checked for `stateVersion` |

---

## 2. Checklist Results

### 2.1 `vexos.btrfs.enable = false` present and correctly placed — PASS

`hosts/vm.nix` contains:

```nix
  # VMs rely on hypervisor memory management — no disk swap file needed.
  vexos.swap.enable = false;
  # VM btrfs layout is not snapper-compatible — disable btrfs/snapper integration.
  vexos.btrfs.enable = false;
```

- Placement is immediately after `vexos.swap.enable = false`, exactly as specified.
- Comment is accurate and stylistically consistent with the adjacent swap comment.
- No extraneous whitespace or formatting issues.

---

### 2.2 Implementation approach matches spec §4.1 (preferred) — PASS

The spec defines two approaches:

| Approach | Description | Preference |
|---|---|---|
| §4.1 | `vexos.btrfs.enable = false` option override | **Preferred** |
| §4.2 | `lib.mkForce` individual service overrides | Alternative |

The implementation uses §4.1. This is the correct choice:

- The `vexos.btrfs.enable` option was introduced specifically to gate the entire
  `lib.mkIf config.vexos.btrfs.enable { ... }` block in `modules/system.nix`.
- A single option assignment suppresses all downstream services, packages, and
  activation scripts at evaluation time — without requiring `lib` in the function
  signature or per-service `mkForce` calls.
- The option description in `modules/system.nix` explicitly states it is intended
  for edge cases such as the VM host.

---

### 2.3 Fix correctly suppresses the snapper module block — PASS

`modules/system.nix` wraps the entire snapper/btrfs block in:

```nix
(lib.mkIf config.vexos.btrfs.enable { ... })
```

Setting `vexos.btrfs.enable = false` causes that block to evaluate as `{}` at
Nix evaluation time, cleanly suppressing:

| Suppressed option | Effect |
|---|---|
| `services.snapper.configs.root` | No snapper systemd units generated |
| `services.snapper.snapshotRootOnBoot = true` | `snapper-boot.service` not created |
| `services.snapper.persistentTimer = true` | No persistent timer |
| `services.btrfs.autoScrub.enable = true` | No btrfs-scrub.service |
| `system.activationScripts.snapperSubvolume` | No subvolume creation on activation |
| `environment.systemPackages` (btrfs packages) | btrfs-assistant/btrfs-progs not added |

This directly resolves the reported `snapper-boot.service` failure
and the secondary `btrfs-scrub` error.

The option is declared in `modules/system.nix`, which is imported through the
chain `hosts/vm.nix` → `../configuration.nix` → `./modules/system.nix`. The
option is in scope; the assignment is type-correct (`bool := false`).

---

### 2.4 Other host files do NOT contain this override — PASS

Verified `hosts/amd.nix`, `hosts/nvidia.nix`, `hosts/intel.nix`:

- None set `vexos.btrfs.enable`.
- All rely on the auto-detection default:
  `(config.fileSystems ? "/") && (config.fileSystems."/".fsType == "btrfs")`
- On real hardware provisioned with a btrfs root, this evaluates to `true` and
  snapper remains fully enabled.
- The fix is correctly scoped to the VM host only.

---

### 2.5 No unintended changes — PASS

`hosts/vm.nix` contains only:
- Pre-existing header comment block
- `imports` (unchanged)
- `networking.hostName` (unchanged)
- `vexos.swap.enable = false` (unchanged)
- `vexos.btrfs.enable = false` (new — the intended change)
- `environment.systemPackages` (unchanged)
- `system.nixos.distroName` (unchanged)

No extraneous changes to any other file.

---

### 2.6 `hardware-configuration.nix` absent from repository — PASS

A workspace-wide file search returned no results for `hardware-configuration.nix`.
The file is correctly absent and remains host-generated at `/etc/nixos/` only.

---

### 2.7 `system.stateVersion` unchanged — PASS

`configuration.nix` line 123:

```nix
system.stateVersion = "25.11";
```

Value is present and unmodified.

---

### 2.8 Build Validation — Cannot verify (Windows host)

`nix flake check` and `nixos-rebuild dry-build` require the Nix CLI, which is not
available on this Windows review host. Attempted execution returned
`CommandNotFoundException`.

**Static analysis (no Nix runtime):**

| Check | Result |
|---|---|
| Nix syntax | Valid — single line bool assignment |
| Option type | `lib.types.bool` — `false` is correct |
| Option in scope | Yes — via `configuration.nix` → `modules/system.nix` |
| Import chain intact | Yes — unchanged from working baseline |
| No new inputs or dependencies | Correct — this change requires no new packages |

Confidence in `nix flake check` success: **high**.

The following commands must be run on the NixOS host to complete build verification:

```bash
cd /path/to/vexos-nix
nix flake check --impure
sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm
sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd
sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia
```

---

## 3. Minor Observations (Non-Critical)

1. **`btrfs-assistant` / `btrfs-progs` not present in VM packages** — The
   `vexos.btrfs.enable = false` suppression removes these packages from the VM's
   `environment.systemPackages`. Per spec §3, this differs from the `lib.mkForce`
   approach (which intentionally kept the packages). This is acceptable: the spec
   preferred approach (§4.1) is used, and the packages are not needed on a VM
   where btrfs integration is disabled. If the user wants them, they can add them
   explicitly.

2. **`lib` not in `hosts/vm.nix` function args** — The `vexos.btrfs.enable = false`
   approach does not require `lib` in the module signature, unlike the `mkForce`
   approach. The current signature `{ inputs, ... }:` is correct and minimal.

---

## 4. Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 100% | A |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | N/A — Nix CLI unavailable on Windows host | — |

**Overall Grade: A (100% of verifiable categories)**  
**Build Success: Cannot verify — run `nix flake check --impure` on NixOS host.**

---

## 5. Summary

The implementation is correct, minimal, and fully aligned with the preferred
approach defined in spec §4.1.

- `vexos.btrfs.enable = false` is present, correctly placed, and type-correct.
- The fix suppresses the entire snapper/btrfs block in `modules/system.nix` at
  evaluation time — no `lib`, no `mkForce`, no per-service overrides needed.
- All real hardware hosts (amd, nvidia, intel) are unaffected.
- `hardware-configuration.nix` is absent from the repository.
- `system.stateVersion` is unchanged.
- No unintended changes to any file.

**Result: PASS**  
Build verification must be confirmed on the NixOS host before merge.

