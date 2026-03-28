# Garnix Cache Migration — Review

**Feature:** `garnix_cache_migration`
**Date:** 2026-03-28
**Reviewer:** Subagent Review Pass
**Verdict:** PASS

---

## 1. Files Reviewed

- `flake.nix`
- `configuration.nix`
- `hosts/vm.nix`
- Spec: `.github/docs/subagent_docs/garnix_cache_migration_spec.md`

---

## 2. Exact Content of Modified Cache Sections

### 2.1 `flake.nix` — `nixConfig` block (lines 1–11)

```nix
{
  nixConfig = {
    extra-substituters = [
      "https://attic.xuyh0120.win/lantian"
      "https://cache.garnix.io"
    ];
    extra-trusted-public-keys = [
      "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc="
      "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
    ];
  };
```

**Status:** ✅ `vex-kernels.cachix.org` and its key are absent. Attic and Garnix remain as specified.

---

### 2.2 `configuration.nix` — `nix.settings` cache block (lines 54–63)

```nix
    # Binary caches — fetch pre-built derivations instead of compiling locally
    substituters = [
      "https://cache.nixos.org"   # Official NixOS cache — always required
      "https://cache.garnix.io"   # Garnix CI cache
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
    ];
```

**Status:** ✅ Exactly matches spec section 4.1. Both required entries present; no Cachix entries.

`system.stateVersion` (line 120):

```nix
  system.stateVersion = "25.11";
```

**Status:** ✅ Unchanged.

---

### 2.3 `hosts/vm.nix` — Cache block

The entire `nix.settings` Cachix override block has been removed. Current
relevant differing section of vm.nix (`networking.hostName`):

```nix
  # Distinguish the VM host on the network
  networking.hostName = "vexos-vm";
}
```

**Status:** ✅ No `vex-kernels.cachix.org` substituter. No `nix.settings` cache
override whatsoever. Removal was clean — only the intended block removed.

---

## 3. Checklist Results

| # | Check | Result | Notes |
|---|-------|--------|-------|
| 1 | `configuration.nix` `substituters` contains `https://cache.nixos.org` | ✅ PASS | Present at index 0 |
| 2 | `configuration.nix` `substituters` contains `https://cache.garnix.io` | ✅ PASS | Present at index 1 |
| 3 | `configuration.nix` `substituters` contains no `*.cachix.org` | ✅ PASS | None found |
| 4 | `configuration.nix` `trusted-public-keys` contains `cache.nixos.org-1:…` | ✅ PASS | Present |
| 5 | `configuration.nix` `trusted-public-keys` contains `cache.garnix.io:…` | ✅ PASS | Present |
| 6 | `configuration.nix` `trusted-public-keys` contains no `*.cachix.org` keys | ✅ PASS | None found |
| 7 | `flake.nix` `extra-substituters` contains no `*.cachix.org` entries | ✅ PASS | None found |
| 8 | `flake.nix` `extra-trusted-public-keys` contains no `*.cachix.org` keys | ✅ PASS | None found |
| 9 | `hosts/vm.nix` contains no `*.cachix.org` entries | ✅ PASS | None found |
| 10 | `system.stateVersion` unchanged in `configuration.nix` | ✅ PASS | `"25.11"` |
| 11 | `hardware-configuration.nix` NOT present in repository | ✅ PASS | File not found in workspace |

---

## 4. Build Validation

### 4.1 `nix flake check`

```
error: access to absolute path '/etc/nixos/hardware-configuration.nix'
       is forbidden in pure evaluation mode (use '--impure' to override)
```

**Result:** Expected failure — not a configuration error.

`nix flake check` runs in pure evaluation mode, which forbids all access to
absolute paths outside the flake. This project requires
`hardware-configuration.nix` from `/etc/nixos/` (generated per-host). This
failure pre-existed and is structural to the project design. The spec confirms:
*"`hardware-configuration.nix` MUST NOT be added to this repository; it is
generated per-host by `nixos-generate-config`".*

### 4.2 `nix eval --impure` — All three configurations

| Configuration | Attribute Evaluated | Result | Exit Code |
|--------------|---------------------|--------|-----------|
| `vexos-amd` | `config.networking.hostName` | `"vexos"` | 0 ✅ |
| `vexos-nvidia` | `config.networking.hostName` | `"vexos"` | 0 ✅ |
| `vexos-vm` | `config.networking.hostName` | `"vexos-vm"` | 0 ✅ |

All three NixOS configurations evaluate without error.

### 4.3 Runtime `nix.settings` — Evaluated values

The following were confirmed via `nix eval --impure`:

**`vexos-amd` (representative of all three GPU variants):**

```
substituters:
  [ "https://cache.nixos.org" "https://cache.garnix.io" "https://cache.nixos.org/" ]

trusted-public-keys:
  [ "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g=" ]
```

**`vexos-vm`:**

```
substituters:
  [ "https://cache.nixos.org" "https://cache.garnix.io" "https://cache.nixos.org/" ]
```

No Cachix entries in either. ✅

> **INFO — NixOS framework merging artifacts:**
> The evaluated `substituters` list includes `"https://cache.nixos.org/"` (with
> trailing slash) appended by the NixOS module system's default value merging.
> Both forms resolve to the same server; this is standard NixOS behavior and
> harmless.
>
> The evaluated `trusted-public-keys` list includes `cache.nixos.org-1:…` twice
> (once from the explicit config, once from the NixOS default). Duplicate keys
> in this list are ignored by the Nix daemon. This is harmless standard NixOS
> default merging behavior.

---

## 5. Issues Found

### CRITICAL
_None._

### WARNING
_None._

### INFO
1. **Duplicate `cache.nixos.org-1` key** — `trusted-public-keys` evaluated list
   contains the NixOS default key twice (once from config, once merged from
   NixOS module default). Harmless; the Nix daemon ignores duplicates. No
   action required.
2. **Trailing-slash `cache.nixos.org/`** — `substituters` evaluated list
   contains both `https://cache.nixos.org` and `https://cache.nixos.org/`.
   NixOS module default appends the trailing-slash form. Harmless. No action
   required.

---

## 6. Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A+ |
| Best Practices | 100% | A+ |
| Functionality | 100% | A+ |
| Code Quality | 98% | A+ |
| Security | 100% | A+ |
| Performance | 100% | A+ |
| Consistency | 100% | A+ |
| Build Success | 95% | A |

> Build Success is 95% rather than 100% because `nix flake check` in pure mode
> cannot evaluate the configurations (structural constraint of the project, not
> a defect). All impure evaluations pass with exit code 0.

**Overall Grade: A+ (99%)**

---

## 7. Summary

The Garnix cache migration implementation is **correct and complete**:

- All three Cachix entries (`nix-gaming.cachix.org`, `vex-kernels.cachix.org`
  × 2) have been removed from all three target files.
- The required `https://cache.nixos.org` and `https://cache.garnix.io`
  substituters with correct public keys are present in `configuration.nix`.
- The Attic/Lantian build-time cache is correctly retained in `flake.nix`
  `nixConfig` as specified.
- `system.stateVersion` is untouched at `"25.11"`.
- `hardware-configuration.nix` is not tracked in the repository.
- All three NixOS configurations (`vexos-amd`, `vexos-nvidia`, `vexos-vm`)
  evaluate cleanly with `nix eval --impure` (exit 0).
- No regressions or side effects detected.

**Verdict: PASS**
