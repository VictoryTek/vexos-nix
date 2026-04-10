# Impermanence Implementation Review — vexos-nix Privacy Role

**Feature:** `impermanence`
**Reviewer:** NixOS Code Review Agent
**Date:** 2026-04-10
**Review Scope:** `modules/impermanence.nix` (NEW), `flake.nix` (MODIFIED), `configuration-privacy.nix` (MODIFIED)
**Reference Files:** `configuration.nix`, `modules/system.nix`, `hosts/privacy-amd.nix`, `hosts/privacy-nvidia.nix`, `hosts/privacy-vm.nix`, `template/etc-nixos-flake.nix`

---

## Build Validation Result

**Status: COULD NOT EXECUTE — Nix unavailable in Windows environment**

Nix is not installed in the native Windows environment or in the available WSL Ubuntu instance (`nix not found`). The following commands could not be executed:
- `nix flake check`
- `sudo nixos-rebuild dry-build --flake .#vexos-privacy-amd`
- `sudo nixos-rebuild dry-build --flake .#vexos-privacy-nvidia`
- `sudo nixos-rebuild dry-build --flake .#vexos-privacy-vm`

A thorough manual Nix syntax and logic review was performed instead. One CRITICAL structural issue was found that would cause evaluation failure on one deployment path. See findings below.

---

## Findings

### CRITICAL

---

#### CRITICAL-01: `modules/impermanence.nix` requires `inputs` as a module arg — breaks `nixosModules.privacyBase` template path

**File:** `flake.nix` (nixosModules.privacyBase definition), `modules/impermanence.nix`

**Description:**

`modules/impermanence.nix` declares `{ config, lib, inputs, ... }:` as its module signature. The `inputs` argument is a named formal parameter, not a variadic `...` capture. In the NixOS module system, named module arguments must be satisfied either by the standard module args set (`config`, `options`, `lib`, `pkgs`, `modulesPath`) or by `specialArgs` / `_module.args` passed to `nixpkgs.lib.nixosSystem`.

**Path 1 — `nixosConfigurations.vexos-privacy-*` (WORKS):**
```nix
nixosConfigurations.vexos-privacy-amd = nixpkgs.lib.nixosSystem {
  inherit system;
  modules = commonModules ++ [ ./hosts/privacy-amd.nix ];
  specialArgs = { inherit inputs; };  # ← inputs provided here
};
```
`inputs` is available. The conditional import in `modules/impermanence.nix` evaluates correctly. ✓

**Path 2 — `nixosModules.privacyBase` via `template/etc-nixos-flake.nix` (BROKEN):**
```nix
# In template/etc-nixos-flake.nix:
_mkVariantWith = baseModule: variant: gpuModule: nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  modules = [ ... baseModule ... ];
  # ← No specialArgs — inputs is NOT available
};
mkPrivacyVariant = _mkVariantWith vexos-nix.nixosModules.privacyBase;
```

`nixosModules.privacyBase` imports `./configuration-privacy.nix`, which imports `./modules/impermanence.nix`. When the module function `{ config, lib, inputs, ... }:` is applied, `inputs` is not in the module args. NixOS will error:

```
error: Function called without required argument 'inputs'
```

This breaks every privacy-role deployment made via the template file, which is the standard end-user deployment path.

**Root cause:** `nixosModules.privacyBase` already imports `impermanence.nixosModules.impermanence` unconditionally at the module level (so the upstream module options are available), but it does not inject `inputs` into `_module.args`, leaving `modules/impermanence.nix`'s conditional import unable to resolve `inputs`.

**Fix:** Add `_module.args.inputs = inputs;` to the `privacyBase` module definition in `flake.nix`. Since `inputs` is in scope in the `outputs` function (via `@inputs`), this injects the flake's own inputs into the NixOS module system for all downstream modules.

```nix
# flake.nix — nixosModules.privacyBase
privacyBase = { ... }: {
  _module.args.inputs = inputs;          # ← ADD THIS LINE
  imports = [
    nix-gaming.nixosModules.pipewireLowLatency
    home-manager.nixosModules.home-manager
    impermanence.nixosModules.impermanence
    ./configuration-privacy.nix
  ];
  home-manager = { ... };
  nixpkgs.overlays = [ ... ];
};
```

**Impact:** High — blocks all template-based privacy deployments. The `nix flake check` would likely pass (it evaluates `nixosConfigurations`, not `nixosModules`), but runtime evaluation via the template at `/etc/nixos/flake.nix` on a user machine would fail.

---

### WARNINGS

---

#### WARNING-01: `zramSwap.enable = true` in `impermanence.nix` is redundant

**File:** `modules/impermanence.nix`

**Description:** `modules/system.nix` already unconditionally enables ZRAM swap with full configuration:
```nix
zramSwap = {
  enable       = true;
  algorithm    = "lz4";
  memoryPercent = 50;
};
```
`modules/impermanence.nix` re-asserts `zramSwap.enable = true` (bare), which is redundant. NixOS option merging means both values agree, so there is no functional conflict, and `algorithm`/`memoryPercent` from `system.nix` are preserved. However, the re-declaration creates confusion about which module "owns" ZRAM configuration.

**Comment quality note:** The inline comment acknowledges this as a deliberate self-documentation choice ("affirmed here so this module is self-documenting"). This is acceptable but could lead to future divergence if `system.nix` ever removes ZRAM.

**Recommendation:** Remove the `zramSwap.enable = true` line from `impermanence.nix` and update the comment to reference `modules/system.nix` as the authoritative ZRAM configuration. Alternatively, keep it but ensure `algorithm` and `memoryPercent` are explicitly set here too for true self-documentation.

---

#### WARNING-02: `electron-36.9.5` in `permittedInsecurePackages` is likely unnecessary for the privacy role

**File:** `configuration-privacy.nix`

**Description:** `nixpkgs.config.permittedInsecurePackages = [ "electron-36.9.5" ]` is carried over from the desktop role. This exception exists to support Heroic Games Launcher, which is a gaming application. The privacy role does not import `modules/gaming.nix`, and `modules/packages.nix` only includes `brave`, `inxi`, `git`, `curl`, `wget`, and `htop` — none of which require Electron.

Permitting insecure packages unnecessarily broadens the attack surface.

**Recommendation:** Remove or comment out `permittedInsecurePackages` from `configuration-privacy.nix`, or explicitly document why it is retained (e.g., if Brave itself bundles an electron dep in a way that triggers this check).

---

#### WARNING-03: `nixosModules.privacyBase` imports impermanence module unconditionally

**File:** `flake.nix`

**Description:** `nixosModules.privacyBase` imports `impermanence.nixosModules.impermanence` regardless of whether `vexos.impermanence.enable` is true. This is not wrong — it makes the upstream module options available before the conditional import in `modules/impermanence.nix` runs — but it means that any consumer of `privacyBase` always has the impermanence upstream module loaded even if they set `vexos.impermanence.enable = false`.

For the primary use case (privacy role with impermanence always enabled), this is correct behaviour. The redundancy is low-risk but worth noting.

---

### RECOMMENDATIONS

---

#### RECOMMENDATION-01: Add `specialArgs = { inherit inputs; }` to `_mkVariantWith` in the template as secondary hardening

**File:** `template/etc-nixos-flake.nix`

**Description:** Even after CRITICAL-01 is fixed via `_module.args.inputs = inputs;` in `privacyBase`, it is defensive to also update the template so that privacy-variant builds explicitly pass specialArgs. This ensures forward-compatibility if future modules added to the privacy stack require `inputs`:

```nix
_mkVariantWith = baseModule: variant: gpuModule: nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  specialArgs = { inputs = vexos-nix.inputs; };  # ← add defensive specialArgs
  modules = [ ... ];
};
```

Note: `vexos-nix.inputs` exposes the upstream flake's inputs to downstream consumers. This is the correct reference since the template's own `inputs` only contains `vexos-nix` and `nixpkgs`.

---

#### RECOMMENDATION-02: Consider making `boot.tmp.cleanOnBoot` comment more explicit

**File:** `modules/impermanence.nix`

**Description:** The comment correctly notes this is "belt-and-suspenders" since `/` as tmpfs is already clean on every boot. This is accurate and the setting is harmless. No code change required; the existing comment is adequate.

---

#### RECOMMENDATION-03: Add `pkgs` removal confirmation comment

**File:** `modules/impermanence.nix`

**Description:** The module signature is `{ config, lib, inputs, ... }:` without `pkgs` — this is correct since no packages are referenced. This is good practice. No change needed, noting it explicitly as a deliberate/correct omission.

---

## Detailed Checklist Results

### 1. Spec Compliance

| Check | Status | Notes |
|---|---|---|
| `vexos.impermanence.enable` option declared | ✓ | Default false |
| `vexos.impermanence.persistentPath` option declared | ✓ | Default "/persistent" |
| `extraPersistDirs`/`extraPersistFiles` options | ✓ | Added beyond spec — improvement |
| Conditional import of upstream impermanence module | ✓ | `lib.optionals cfg.enable` |
| `vexos.swap.enable = lib.mkForce false` | ✓ | Correct use of mkForce |
| `users.mutableUsers = false` | ✓ | |
| Volatile journald | ✓ | Storage=volatile, RuntimeMaxUse=64M |
| Suppress sudo lecture | ✓ | Defaults lecture = never |
| `hideMounts = true` | ✓ | |
| `/var/lib/nixos` persisted | ✓ | |
| NetworkManager connections NOT persisted | ✓ | Privacy default, commented guidance |
| Bluetooth NOT persisted | ✓ | Privacy default, commented guidance |
| machine-id NOT persisted | ✓ | Privacy default, commented guidance |
| User home fully ephemeral | ✓ | Documented with opt-in guidance |
| Assertion for tmpfs root check | ✓ | |
| Assertion for neededForBoot check | ✓ | |
| `imp` input added to flake | ✓ | No follows (correct — no nixpkgs dep) |
| `impermanence` destructured in outputs | ✓ | |
| `modules/impermanence.nix` imported in `configuration-privacy.nix` | ✓ | |
| `vexos.impermanence.enable = true` in privacy config | ✓ | |
| `users.nimda.initialPassword = "vexos"` set | ✓ | Documented as session password |
| Privacy hosts unchanged | ✓ | Spec 4.6 correctly states no changes needed |
| Privacy flake outputs declared | ✓ | All four GPU variants present |

**Spec note:** The spec (Section 4.5) incorrectly specified `inputs.nixpkgs.follows` and `inputs.home-manager.follows` for the impermanence input. The implementation CORRECTLY deviates by omitting these follows (impermanence has no nixpkgs or home-manager dependency). This is a positive correction.

### 2. Nix Syntax Correctness

| Check | Status |
|---|---|
| Module structure (`options`/`config` separation) | ✓ |
| `let ... in` structure | ✓ |
| `lib.mkIf`, `lib.mkOption`, `lib.types` usage | ✓ |
| String interpolation (`${}`) | ✓ |
| List syntax `[ ... ]` | ✓ |
| Attribute set syntax `{ ... }` | ✓ |
| Semicolons on attribute assignments | ✓ |
| No `builtins.fetchTarball` (uses flake inputs) | ✓ |
| `lib.mkForce` usage | ✓ |
| `lib.optionals` usage | ✓ |
| Assertion structure | ✓ |

No syntax errors detected via manual review. The `or false` fallback on `neededForBoot` attribute access is correct NixOS pattern.

### 3. Flake Input Correctness

| Check | Status | Notes |
|---|---|---|
| `impermanence.url` correct | ✓ | `github:nix-community/impermanence` |
| No incorrect `follows` added | ✓ | Correctly omitted |
| `impermanence` destructured in outputs function | ✓ | `outputs = { ..., impermanence, ... }@inputs:` |
| `inputs.impermanence.nixosModules.impermanence` reference | ✓ | In `modules/impermanence.nix` imports |
| Privacy flake outputs provide `specialArgs = { inherit inputs; }` | ✓ | All `vexos-privacy-*` configs |
| `nixosModules.privacyBase` provides inputs to module system | ✗ | **CRITICAL-01** — missing `_module.args.inputs` |

### 4. Module Integration

| Check | Status |
|---|---|
| `modules/impermanence.nix` imported in `configuration-privacy.nix` | ✓ |
| `specialArgs` provides `inputs` for `nixosConfigurations` | ✓ |
| `specialArgs` NOT provided for `nixosModules.privacyBase` path | ✗ (CRITICAL-01) |
| Privacy role sets `vexos.impermanence.enable = true` | ✓ |
| Desktop/HTPC/Server roles unaffected (module not imported) | ✓ |

### 5. Privacy Best Practices

| Check | Status | Notes |
|---|---|---|
| Stateless root (tmpfs) | ✓ | Documented requirement in hardware-configuration.nix |
| WiFi credentials not saved | ✓ | NetworkManager explicitly excluded |
| Bluetooth pairings not saved | ✓ | Explicitly excluded |
| Browser history not saved | ✓ | No home directory persistence |
| System logs ephemeral | ✓ | Storage=volatile |
| Crash dumps ephemeral | ✓ | Not persisted |
| machine-id not persisted | ✓ | Boot correlation prevented |
| SSH host keys not persisted | ✓ | Privacy default with opt-in guidance |
| `users.mutableUsers = false` | ✓ | Runtime password changes don't survive reboot |

### 6. Swap / ZRAM Interaction

| Check | Status | Notes |
|---|---|---|
| `vexos.swap.enable = lib.mkForce false` | ✓ | Correctly prevents swapfile at `/var/lib/swapfile` on tmpfs |
| `zramSwap.enable = true` in `system.nix` (unconditional) | ✓ | Primary ZRAM config |
| `zramSwap.enable = true` in `impermanence.nix` (redundant) | ⚠ | WARNING-01 — redundant but harmless |
| `vexos.btrfs.enable` auto-detects tmpfs root as non-btrfs | ✓ | Default logic correctly evaluates false on tmpfs |
| No swap config conflict | ✓ | `mkForce` ensures no priority ambiguity |

### 7. Security

| Check | Status | Notes |
|---|---|---|
| `initialPassword = "vexos"` documented as session default | ✓ | Temporary; persists changes do not survive reboot |
| No hardcoded sensitive data | ✓ | |
| LUKS encryption required at hardware level | ✓ | Documented in PREREQUISITES comment |
| No world-readable secret paths persisted | ✓ | |
| `permittedInsecurePackages` includes unnecessary `electron-36.9.5` | ⚠ | WARNING-02 |

### 8. Hardware Compatibility

| Check | Status | Notes |
|---|---|---|
| AMD drivers (`amdgpu`) in `/nix/store` | ✓ | Fully compatible with tmpfs root |
| NVIDIA drivers in `/nix/store` | ✓ | `nvidia-persistenced` state is ephemeral — acceptable |
| VM guest drivers in `/nix/store` | ✓ | VirtIO/QXL/SPICE unaffected |
| `hosts/privacy-vm.nix` adds Up package via `inputs` | ✓ | Template requires `inputs` specialArg — already present in direct flake outputs |
| No GPU-specific paths requiring persistence identified | ✓ | |

---

## Score Table

| Category | Score | Grade |
|---|---|---|
| Specification Compliance | 96% | A |
| Best Practices | 82% | B |
| Functionality | 85% | B |
| Code Quality | 90% | A- |
| Security | 88% | B+ |
| Performance | 95% | A |
| Consistency | 88% | B+ |
| Build Success | N/A | UNTESTED* |

*Build could not be executed (Nix unavailable on Windows). Manual review suggests the `nixosConfigurations.vexos-privacy-*` outputs are structurally sound. The `nixosModules.privacyBase` path has a confirmed critical defect.

**Overall Grade: B+ (89%) — pending CRITICAL-01 fix**

---

## Final Verdict

### NEEDS_REFINEMENT

---

### CRITICAL Issues That Must Be Fixed

#### CRITICAL-01 — `nixosModules.privacyBase` does not inject `inputs` into the module system

**File to fix:** `c:\Projects\vexos-nix\flake.nix`

**Change required:** In the `nixosModules.privacyBase` definition, add `_module.args.inputs = inputs;` as the first attribute:

```nix
# BEFORE:
privacyBase = { ... }: {
  imports = [
    nix-gaming.nixosModules.pipewireLowLatency
    home-manager.nixosModules.home-manager
    impermanence.nixosModules.impermanence
    ./configuration-privacy.nix
  ];
  home-manager = { ... };
  nixpkgs.overlays = [ ... ];
};

# AFTER:
privacyBase = { ... }: {
  _module.args.inputs = inputs;          # ← Inject flake inputs so modules/impermanence.nix can reference them
  imports = [
    nix-gaming.nixosModules.pipewireLowLatency
    home-manager.nixosModules.home-manager
    impermanence.nixosModules.impermanence
    ./configuration-privacy.nix
  ];
  home-manager = { ... };
  nixpkgs.overlays = [ ... ];
};
```

**Why this works:** `inputs` is in scope in the flake `outputs` function (via `@inputs`). `_module.args.inputs = inputs` injects the vexos-nix flake's own inputs into the NixOS module system, making `inputs` available as a named module argument to all downstream modules — including `modules/impermanence.nix`. This allows `lib.optionals cfg.enable [inputs.impermanence.nixosModules.impermanence]` to evaluate without requiring the template consumer to pass `specialArgs`.

---

### Recommended Fixes (Not Blocking)

1. **Remove redundant `zramSwap.enable = true`** from `modules/impermanence.nix` or keep it with clarified ownership comment (WARNING-01).
2. **Remove `electron-36.9.5`** from `permittedInsecurePackages` in `configuration-privacy.nix` if Brave browser does not require it (WARNING-02).
3. **Add secondary hardening** to `template/etc-nixos-flake.nix` by injecting `specialArgs = { inputs = vexos-nix.inputs; }` in the `_mkVariantWith` helper (RECOMMENDATION-01).
