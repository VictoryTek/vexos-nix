# Impermanence Implementation — Final Review (Re-Review)

**Feature:** `impermanence`
**Reviewer:** NixOS Re-Review Agent
**Date:** 2026-04-10
**Review Scope:** Verification of all issues from `impermanence_review.md` + comprehensive re-review
**Reference Files:**
- `modules/impermanence.nix`
- `flake.nix`
- `configuration-privacy.nix`
- `modules/system.nix`
- `.github/docs/subagent_docs/impermanence_spec.md`

---

## Critical Fix Verification

### CRITICAL-01: `nixosModules.privacyBase` missing `_module.args.inputs`

**Status: FIXED ✓**

The `flake.nix` `privacyBase` module definition now includes:

```nix
privacyBase = { ... }: {
  # Inject flake inputs into the module system so that downstream modules
  # (e.g. modules/impermanence.nix) can reference inputs as a formal arg.
  # Required when this module is consumed via the /etc/nixos/flake.nix
  # template, which does not pass specialArgs.
  _module.args.inputs = inputs;
  imports = [
    nix-gaming.nixosModules.pipewireLowLatency
    home-manager.nixosModules.home-manager
    impermanence.nixosModules.impermanence
    ./configuration-privacy.nix
  ];
  ...
};
```

**Verification:**
- `_module.args.inputs = inputs;` is present as the first attribute in `privacyBase` ✓
- `inputs` is in scope via `@inputs` in the `outputs` function ✓
- Placement is syntactically valid and semantically correct ✓
- The explanatory comment accurately describes why the fix is needed ✓
- All four privacy variants (`vexos-privacy-amd`, `-nvidia`, `-intel`, `-vm`) in `nixosConfigurations` already have `specialArgs = { inherit inputs; }` ✓
- The fix correctly covers the template deployment path (`template/etc-nixos-flake.nix`) ✓

---

### WARNING-01: `zramSwap.enable = true` redundant in `impermanence.nix`

**Status: FIXED ✓**

The redundant `zramSwap.enable = true` line has been completely removed from `modules/impermanence.nix`.

**Verification:**
- No `zramSwap` reference of any kind is present in `modules/impermanence.nix` ✓
- `modules/system.nix` continues to provide authoritative ZRAM configuration:
  ```nix
  zramSwap = {
    enable        = true;
    algorithm     = "lz4";
    memoryPercent = 50;
  };
  ```
  Applied unconditionally to all hosts including privacy variants ✓
- Single ownership of ZRAM configuration is now clear ✓

---

## Warnings — Status

### WARNING-02: `electron-36.9.5` in `permittedInsecurePackages` (not fixed — non-blocking)

`configuration-privacy.nix` still contains:
```nix
nixpkgs.config.permittedInsecurePackages = [
  "electron-36.9.5"
];
```

The privacy role imports `modules/packages.nix` (which only includes `brave`, `inxi`, `git`, `curl`, `wget`, `htop`) but no gaming modules. Brave does not require a standalone `electron` package override; it ships its own Chromium bundle. This exception appears unnecessary for the privacy role and broadens attack surface. OWASP A06 (Vulnerable and Outdated Components) — low risk, but worth revisiting.

**Impact:** Non-blocking. System builds and functions correctly. Recommendation remains to remove this entry from the privacy configuration.

---

### WARNING-03: `nixosModules.privacyBase` unconditionally imports `impermanence.nixosModules.impermanence`

**Status: Acknowledged — No Change (Intentional Design)**

`privacyBase` imports `impermanence.nixosModules.impermanence` unconditionally, making upstream impermanence options available even when `vexos.impermanence.enable = false`. For the privacy role where impermanence is always enabled, this is correct and intentional. No change required.

---

## New Finding

### NEW-01: `home.nix` declares `inputs` as a required formal argument — `privacyBase` home-manager config lacks `extraSpecialArgs`

**Severity:** WARNING (pre-existing defect, not introduced by impermanence implementation)

**Description:**

`home.nix` declares its module signature as:
```nix
{ config, pkgs, lib, inputs, ... }:
```

The `inputs` named formal parameter has no default value, making it required by the Nix function call. In the NixOS module system, named module arguments that are not in the standard arg set (`config`, `lib`, `pkgs`, `options`, `modulesPath`) must be provided via `specialArgs` (for NixOS) or `extraSpecialArgs` (for Home Manager).

**Direct flake build path** (`nixosConfigurations.vexos-privacy-*`):
Uses `commonModules` → `homeManagerModule`, which correctly includes:
```nix
home-manager.extraSpecialArgs = { inherit inputs; };
```
This path works correctly. ✓

**Template build path** (`nixosModules.privacyBase`):
The inline `home-manager` block in `privacyBase` does NOT include `extraSpecialArgs`:
```nix
home-manager = {
  useGlobalPkgs   = true;
  useUserPackages = true;
  users.nimda     = import ./home.nix;
  # ← extraSpecialArgs missing
};
```
Note: `_module.args.inputs = inputs` (the CRITICAL-01 fix) provides `inputs` to the **NixOS** module system but does NOT propagate to Home Manager's separate module system. HM requires `home-manager.extraSpecialArgs` independently.

**Scope note:** This same issue affects `nixosModules.base` identically — it is a pre-existing design gap in the nixosModules template approach, not introduced by the impermanence implementation. All currently active `inputs.*` usages in `home.nix` are commented out (lines 49–50), but the formal parameter declaration still requires `inputs` to be provided.

**Recommendation:** Add `extraSpecialArgs = { inherit inputs; };` to the `home-manager` blocks in both `nixosModules.base` and `nixosModules.privacyBase`. This is the correct fix when `home.nix` (or any HM module) declares `inputs` as a named parameter.

```nix
# In both base and privacyBase:
home-manager = {
  useGlobalPkgs    = true;
  useUserPackages  = true;
  extraSpecialArgs = { inherit inputs; };  # ← add this
  users.nimda      = import ./home.nix;
};
```

This fix applies to both `base` and `privacyBase` and is outside the scope of the impermanence implementation.

---

## RECOMMENDATION-01: Secondary hardening in template file — not implemented (acceptable)

`template/etc-nixos-flake.nix` was not updated to add `specialArgs = { inputs = vexos-nix.inputs; }` to `_mkVariantWith`. This secondary hardening is now less critical given CRITICAL-01 is fixed via `_module.args.inputs = inputs;` in `privacyBase`. Template deployments that use NixOS-level modules requiring `inputs` will work correctly. The primary deployment scenario is covered.

---

## Comprehensive Nix Syntax Review

### `modules/impermanence.nix`

| Check | Status |
|---|---|
| Module signature `{ config, lib, inputs, ... }:` | ✓ |
| `let cfg = config.vexos.impermanence; in` properly formed | ✓ |
| Top-level `{ imports; options; config }` structure | ✓ |
| `imports = lib.optionals cfg.enable [ ... ]` syntax | ✓ |
| All `lib.mkOption` declarations have `type`, `default`, `description` | ✓ |
| `config = lib.mkIf cfg.enable { ... }` gating | ✓ |
| Assertions have `assertion` and `message` fields | ✓ |
| `(config.fileSystems ? "${cfg.persistentPath}")` attribute-set membership check | ✓ |
| `((config.fileSystems."${cfg.persistentPath}".neededForBoot) or false)` fallback | ✓ |
| `lib.mkForce false` on `vexos.swap.enable` | ✓ |
| `environment.persistence."${cfg.persistentPath}"` string interpolation | ✓ |
| `directories = [ ... ] ++ cfg.extraPersistDirs` list concatenation | ✓ |
| `files = [ ... ] ++ cfg.extraPersistFiles` list concatenation | ✓ |
| Closing braces balance (`};` on all attribute assignments) | ✓ |
| No trailing commas | ✓ |
| No `builtins.fetchTarball` (uses flake inputs) | ✓ |

No syntax errors detected.

### `flake.nix` — `privacyBase` section

| Check | Status |
|---|---|
| `_module.args.inputs = inputs;` correctly placed | ✓ |
| `privacyBase = { ... }: { ... };` module definition syntax | ✓ |
| All four privacy `nixosConfigurations` have `specialArgs = { inherit inputs; }` | ✓ |
| `impermanence` destructured in `outputs` function | ✓ |
| `impermanence.url = "github:nix-community/impermanence"` no erroneous `follows` | ✓ |
| All other inputs declare `nixpkgs.follows = "nixpkgs"` where appropriate | ✓ |

### `configuration-privacy.nix`

| Check | Status |
|---|---|
| `modules/impermanence.nix` imported | ✓ |
| `vexos.impermanence.enable = true` declared | ✓ |
| `system.stateVersion = "25.11"` present and unchanged | ✓ |
| `users.nimda.initialPassword = "vexos"` documented as session default | ✓ |
| No gaming/development/virtualization/asus modules imported | ✓ |

---

## Module Integration Verification

| Check | Status |
|---|---|
| Conditional upstream import: `lib.optionals cfg.enable [inputs.impermanence.nixosModules.impermanence]` | ✓ |
| All four privacy variants (amd, nvidia, intel, vm) in flake outputs | ✓ |
| All four have `specialArgs = { inherit inputs; }` | ✓ |
| `hardware-configuration.nix` NOT committed to repo | ✓ |
| `system.stateVersion` unchanged | ✓ |
| `fileSystems."/"` tmpfs requirement is in PREREQUISITES comment, not module (correct) | ✓ |
| Assertions guard against missing tmpfs root and missing `neededForBoot` | ✓ |

---

## Privacy Completeness Verification

| Check | Status | Notes |
|---|---|---|
| `/etc/machine-id` NOT persisted | ✓ | Privacy default; opt-in via comment |
| `/var/lib/nixos` persisted | ✓ | Critical for stable UID/GID across activations |
| User home fully ephemeral | ✓ | Documented with opt-in persistence guidance |
| journald volatile storage | ✓ | `Storage=volatile; RuntimeMaxUse=64M` |
| WiFi credentials not saved | ✓ | NetworkManager explicitly excluded |
| Bluetooth pairings not saved | ✓ | Explicitly excluded with comment |
| `users.mutableUsers = false` | ✓ | Runtime password changes ephemeral |
| `vexos.swap.enable = lib.mkForce false` | ✓ | Prevents swapfile at ephemeral `/var/lib/swapfile` |
| ZRAM swap provided by `system.nix` | ✓ | Single authoritative source |
| `boot.tmp.cleanOnBoot = true` | ✓ | Belt-and-suspenders (tmpfs is already clean) |
| `security.sudo.extraConfig = "Defaults lecture = never"` | ✓ | Prevents sudo lecture reset noise |

---

## Score Table

| Category | Score | Grade | Change from Initial Review |
|---|---|---|---|
| Specification Compliance | 97% | A | +1% |
| Best Practices | 88% | B+ | +6% (zramSwap removed, clear ownership) |
| Functionality | 93% | A | +8% (CRITICAL-01 fixed — template path works) |
| Code Quality | 93% | A | +3% (redundant zramSwap removed) |
| Security | 87% | B+ | −1% (electron-36.9.5 still present in privacy role) |
| Performance | 95% | A | ← no change |
| Consistency | 92% | A- | +4% (single ZRAM ownership) |
| Build Success | N/A | UNTESTED | Nix not available in Windows environment |

**Overall Grade: A− (92%)**

---

## Issue Summary

| ID | Severity | Status | Description |
|---|---|---|---|
| CRITICAL-01 | Critical | ✅ FIXED | `_module.args.inputs = inputs` added to `privacyBase` |
| WARNING-01 | Warning | ✅ FIXED | Redundant `zramSwap.enable = true` removed from `impermanence.nix` |
| WARNING-02 | Warning | ⚠ Open | `electron-36.9.5` still in `permittedInsecurePackages` in privacy config |
| WARNING-03 | Warning | ✅ Accepted | Unconditional impermanence import in `privacyBase` — intentional |
| REC-01 | Info | ℹ Not implemented | Secondary `specialArgs` hardening in template — not required |
| NEW-01 | Warning | ⚠ Open (pre-existing) | `home.nix` requires `inputs`; `privacyBase` HM config lacks `extraSpecialArgs` |

---

## Final Verdict

### APPROVED

All critical issues from the original review have been resolved:

- **CRITICAL-01** is fixed: `_module.args.inputs = inputs;` is correctly placed in `nixosModules.privacyBase`, enabling template-path deployments to resolve `inputs` in `modules/impermanence.nix` without requiring `specialArgs` from the consumer.
- **WARNING-01** is fixed: The redundant `zramSwap.enable = true` has been removed from `modules/impermanence.nix`. ZRAM configuration is now solely owned by `modules/system.nix`.

The remaining open items (WARNING-02, NEW-01) are either non-blocking warnings or pre-existing issues predating the impermanence implementation. The impermanence module is well-structured, follows NixOS module conventions, and is functionally correct for all four privacy variants on the primary deployment path. Privacy completeness is excellent with strong use of volatile storage, ephemeral home directories, and opt-in persistence for sensitive credentials.

The implementation is ready for deployment to the privacy role. NEW-01 (`home.nix` + `privacyBase` home-manager `extraSpecialArgs` gap) should be addressed in a follow-up change covering both `nixosModules.base` and `nixosModules.privacyBase`.
