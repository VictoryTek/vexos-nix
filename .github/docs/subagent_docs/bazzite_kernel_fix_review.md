# Bazzite Kernel Fix — Review

**Feature Name:** `bazzite_kernel_fix`  
**Date:** 2026-04-01  
**Reviewer:** QA Subagent  
**Status:** PASS

---

## 1. Files Validated

| File | Status |
|------|--------|
| `hosts/vm.nix` | ✅ Matches specification |
| `flake.nix` | ✅ Matches specification |
| `flake.lock` | ✅ kernel-bazzite updated to `ce01769` head |

---

## 2. Code Review Findings

### `hosts/vm.nix`

| Check | Result |
|-------|--------|
| `boot.kernelPackages = lib.mkOverride 49 (pkgs.linuxPackagesFor inputs.kernel-bazzite.packages.x86_64-linux.linux-bazzite)` present | ✅ |
| `lib.makeOverridable` removed | ✅ |
| `overrideAttrs` removed | ✅ |
| `rawKernel` / `kernelWithFeatures` / `bazziteKernel` let-bindings removed | ✅ |
| `networking.hostName = "vexos-vm"` present | ✅ |
| Bootloader example comments preserved | ✅ |
| Function signature is `{ pkgs, lib, inputs, ... }:` | ✅ |
| Imports are `../configuration.nix` and `../modules/gpu/vm.nix` | ✅ |
| New comment block explains cache-miss rationale for direct input reference | ✅ (added clarity) |

### `flake.nix`

| Check | Result |
|-------|--------|
| `packages.x86_64-linux.linux-bazzite = kernel-bazzite.packages.x86_64-linux.linux-bazzite;` (direct, no `.overrideAttrs`) | ✅ |
| `nixosModules.kernelBazzite` uses direct `pkgs.linuxPackagesFor kernel-bazzite.packages.x86_64-linux.linux-bazzite` | ✅ |
| No `passthru`, `overrideAttrs`, or `makeOverridable` in affected outputs | ✅ |
| `nixosConfigurations.vexos-vm` uses `specialArgs = { inherit inputs; }` | ✅ |
| `nixosConfigurations.vexos-vm` uses `modules = commonModules ++ [ ./hosts/vm.nix ]` | ✅ |
| `kernel-bazzite.url = "github:VictoryTek/vex-kernels"` unchanged | ✅ |
| `system.stateVersion` not touched | ✅ (`"25.11"` in `configuration.nix`, unmodified) |

### `flake.lock`

| Check | Result |
|-------|--------|
| `kernel-bazzite` rev updated from `d612bf2871f1b7e21a6acf13a8a359e655edefec` | ✅ |
| New rev starts with `ce01769` (short hash confirmed in `nix flake update` output) | ✅ |
| Actual full rev in lock: `ce017693c07490274b14f6e052892c9c965953f7` | ✅ |
| Spec note: "or newer if main has advanced" — applies; lock rev differs from spec's predicted `ce01769ecf…` | ✅ (expected, per spec) |

**Minor note:** The spec predicted the full rev as `ce01769ecf6bc51b80b8cc5ad1f51e6c394a3283`. The lock contains `ce017693c07490274b14f6e052892c9c965953f7`. Both share the 7-char prefix `ce01769` that appeared in the `nix flake update` terminal output. The spec explicitly anticipated this with the phrase "or newer if main has advanced." This is not a defect.

---

## 3. Sanity Checks

| Check | Result |
|-------|--------|
| `hardware-configuration.nix` NOT tracked in git | ✅ (`git ls-files` returned empty) |
| `system.stateVersion = "25.11"` present in `configuration.nix` | ✅ |
| No workaround symbols (`makeOverridable`, `overrideAttrs`, `rawKernel`, etc.) in `hosts/vm.nix` or `flake.nix` | ✅ (grep returned no matches) |

---

## 4. Build Validation

### `nix flake check --impure`

```
warning: Git tree '/var/home/nimda/Projects/vexos-nix' has uncommitted changes
warning: Using 'builtins.derivation' to create a derivation named 'options.json' that references
         the store path '...' without a proper context. [×4]
EXIT: 0
```

**Result: PASS** — only pre-existing warnings; no errors.

Note: `nix flake check` (pure mode) correctly fails with "access to absolute path '/etc/nixos/hardware-configuration.nix' is forbidden in pure evaluation mode." This is pre-existing, by design, and not a defect introduced by this PR. Impure mode passes cleanly.

The `builtins.derivation` context warnings are pre-existing and originate from a third-party module (likely home-manager or nix-gaming). Not introduced by this PR.

### `nix eval --impure .#nixosConfigurations.vexos-vm.config.boot.kernelPackages.kernel.version`

```
"6.17.7-ba28"
EXIT: 0
```

**Result: PASS** — Bazzite kernel is selected for the VM configuration.

### `nix eval --impure .#nixosConfigurations.vexos-amd.config.boot.kernelPackages.kernel.version`

```
"6.19.9"
EXIT: 0
```

**Result: PASS** — AMD configuration is unaffected; still uses CachyOS kernel.

### `nix eval --impure .#packages.x86_64-linux.linux-bazzite.version`

```
"6.17.7-ba28"
EXIT: 0
```

**Result: PASS** — packages output is the correct Bazzite kernel artifact, matching the Garnix cache expectation.

---

## 5. Issues Found

### CRITICAL
None.

### RECOMMENDED
None.

### INFORMATIONAL
1. **flake.lock rev differs slightly from spec prediction** — The spec predicted full hash `ce01769ecf6bc51b80b8cc5ad1f51e6c394a3283`; the lock contains `ce017693c07490274b14f6e052892c9c965953f7`. Short prefix `ce01769` matches. Spec text accounts for this: "or newer if main has advanced." No action needed.
2. **`nix flake check` pure mode fails** — Pre-existing design constraint; use `--impure` locally or evaluate configurations individually. Not introduced by this PR.
3. **`builtins.derivation` context warnings** — Pre-existing, originate from upstream modules. Out of scope for this PR.

---

## 6. Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A+ |
| Best Practices | 98% | A+ |
| Functionality | 100% | A+ |
| Code Quality | 98% | A+ |
| Security | 100% | A+ |
| Performance | 100% | A+ |
| Consistency | 100% | A+ |
| Build Success | 100% | A+ |

**Overall Grade: A+ (99.5%)**

Score rationale: The -2% on Best Practices and Code Quality reflects the minor informational note that the spec-predicted commit hash and the actual lock hash have a 7-char shared prefix but differ in full form. This is expected behaviour with floating `main` branch inputs and is acknowledged in the spec itself. No correctness impact.

---

## 7. Review Verdict

**PASS**

All modified files match the specification. All workaround code removed. The Bazzite kernel (`6.17.7-ba28`) is confirmed selected for `vexos-vm`. AMD and package outputs evaluate cleanly. `nix flake check --impure` exits 0. `hardware-configuration.nix` is not tracked. `system.stateVersion` is unchanged.
