# Review: NVIDIA Legacy Driver Support
**Feature Name:** `nvidia_legacy_drivers`
**Review File:** `.github/docs/subagent_docs/nvidia_legacy_drivers_review.md`
**Date:** 2026-04-02
**Reviewer:** QA Subagent (Phase 3)
**Spec:** `.github/docs/subagent_docs/nvidia_legacy_drivers_spec.md`
**Implementation:** `modules/gpu/nvidia.nix`

---

## Score Table

| Category | Score | Grade |
|---|---|---|
| Specification Compliance | 100% | A+ |
| Best Practices | 95% | A |
| Functionality | 100% | A+ |
| Code Quality | 95% | A |
| Security | 100% | A+ |
| Performance | 100% | A+ |
| Consistency | 100% | A+ |
| Build Success | N/A | — |

**Overall Grade: A+ (99%)**

---

## Build Result

**Not verifiable in this environment.**

Neither a native `nix` CLI nor a WSL-hosted Nix installation is available on this Windows
machine (`where.exe nix` → not found; `wsl -e which nix` → not found).

**Assessment basis:** Static inspection of Nix syntax and semantic correctness.
Nix syntax is correct, attribute paths are valid per spec and nixpkgs source, and no infinite
recursion risk was identified. Per task instructions, the absent build is NOT treated as CRITICAL.

---

## 1. Specification Compliance — 100% A+

All requirements from Section 4.3 of the spec are implemented exactly and in full.

| Requirement | Result |
|---|---|
| `options.vexos.gpu.nvidiaDriverVariant` declared | ✓ line 29 |
| Enum type: `["latest", "legacy_535", "legacy_470", "legacy_390"]` | ✓ exact match |
| Default `"latest"` | ✓ |
| `hardware.nvidia.package` driven by option via `driverPackage` let-binding | ✓ |
| `hardware.nvidia.open = false` for all legacy variants (via `useOpen = variant == "latest"`) | ✓ |
| `nvidia-vaapi-driver` excluded for legacy via `lib.mkIf useOpen` | ✓ |
| `options` / `config` split at module root | ✓ |
| Header comment with per-variant GPU generation guidance | ✓ |
| `hosts/nvidia.nix` unchanged (backward-compatible default) | ✓ |

No deviations from the specification were found.

---

## 2. Nix Correctness

### 2.1 `options` / `config` split

The module returns an attribute set with `options.vexos.gpu.nvidiaDriverVariant` and
`config = { ... }` as sibling top-level keys of the module's return value. This is the required
structure for any NixOS module that both declares options and applies configuration. **Correct.**

### 2.2 `let` bindings and `config` argument usage

```nix
let
  variant = config.vexos.gpu.nvidiaDriverVariant;
  driverPackage = if variant == "latest" then ...
  useOpen = variant == "latest";
in
```

The `config` referenced here is the **merged system configuration** passed in via the module
function argument `{ config, pkgs, lib, ... }`. Reading `config.vexos.gpu.nvidiaDriverVariant`
from the let-block is standard NixOS module practice — the option is declared with a default so
it always has a value. No infinite recursion risk: the let-bindings compute scalar values from
already-merged external config; they do not feed back into the option declaration itself.

### 2.3 Attribute paths in `config.boot.kernelPackages.nvidiaPackages.*`

`legacy_535`, `legacy_470`, `legacy_390`, and `stable` all exist in
`pkgs/os-specific/linux/nvidia-x11/default.nix` in nixpkgs for both `nixos-25.05` and `nixos-25.11`
(the channel used by this flake). All are lazy-evaluated — the `driverPackage` mapping only
evaluates the selected variant's path at build time, so un-selected legacy paths are never
fetched for default `"latest"` builds.

### 2.4 `lib.mkIf` on a list-type option

`hardware.graphics.extraPackages = lib.mkIf useOpen (with pkgs; [ nvidia-vaapi-driver ])`

`hardware.graphics.extraPackages` is a list option; NixOS merges contributions from all modules.
`modules/gpu.nix` (always imported via `configuration.nix`) contributes the base list
`[libva, libva-vdpau-driver, ...]`. This module conditionally appends `nvidia-vaapi-driver` via
`lib.mkIf`. When `useOpen = false`, `lib.mkIf` removes this module's contribution from the merge,
leaving only the base packages. This is correct and idiomatic.

### 2.5 `abort` fallback

The else-branch `abort "vexos.gpu.nvidiaDriverVariant: unknown value '${variant}'"` is
unreachable in normal usage because `lib.types.enum` enforces valid values before config is
applied. It is **dead code**, but harmless and a defensible style choice for catching potential
future misuse (e.g., if the type constraint were ever removed). Flagged as RECOMMENDED cleanup
below.

---

## 3. Backward Compatibility

With the default `"latest"`:

| Setting | Before | After | Match |
|---|---|---|---|
| `hardware.nvidia.open` | `true` | `useOpen = true` | ✓ |
| `hardware.nvidia.package` | `nvidiaPackages.stable` | `nvidiaPackages.stable` | ✓ |
| `nvidia-vaapi-driver` included | yes | `lib.mkIf true` → yes | ✓ |
| `hardware.nvidia.modesetting.enable` | `true` | `true` | ✓ |
| `powerManagement.enable` | `false` | `false` | ✓ |
| `powerManagement.finegrained` | `false` | `false` | ✓ |

Behavior is **identical** to the pre-change module when the default is used.
`hosts/nvidia.nix` requires no edits for existing Turing+ installations.

---

## 4. Best Practices

The module demonstrates strong adherence to NixOS module authoring conventions:

- Header comment block clearly states purpose, import restriction, and all variant options.
- Inline comments at every non-obvious decision point (`useOpen`, `driverPackage` mapping,
  `lib.mkIf` for vaapi, `finegrained` power management note).
- Option `description` string is detailed and provides GPU-generation examples for all four values.
- `let`-binding strategy keeps the `config` block concise and readable.
- Uses `lib.mkIf` (standard idiomatic NixOS conditional) rather than ad-hoc `if-then-else` in
  the config body.

Minor deduction (−5%): the `abort` dead-code branch adds minor noise; see RECOMMENDED below.

---

## 5. Security

No security concerns. This module configures GPU driver selection — a purely local hardware
configuration concern. No secrets, no network access, no privilege escalation paths.

---

## 6. Performance

The module has no runtime performance implications beyond selecting the correct driver package.
Lazy evaluation of `driverPackage` ensures un-selected legacy driver paths are not fetched
during a default `"latest"` build.

---

## 7. Consistency

The module is fully consistent with:
- Existing module style in `modules/gpu/amd.nix` (no options declared there, but structure
  follows project conventions).
- The `vexos.*` option namespace is unique — no other module in the project declares any
  `vexos.*` options (confirmed by grep across all `.nix` files). No namespace conflicts.
- `hardware.graphics.extraPackages` additions are consistent with `modules/gpu.nix` which also
  contributes to the same merged list.

---

## CRITICAL Issues

**None.**

No blocking issues were found. The implementation is correct, complete, and safe.

---

## RECOMMENDED Improvements

### R1 — Remove the unreachable `abort` branch (LOW priority)

```nix
-- current
  driverPackage =
    if variant == "latest"          then config.boot.kernelPackages.nvidiaPackages.stable
    else if variant == "legacy_535" then config.boot.kernelPackages.nvidiaPackages.legacy_535
    else if variant == "legacy_470" then config.boot.kernelPackages.nvidiaPackages.legacy_470
    else if variant == "legacy_390" then config.boot.kernelPackages.nvidiaPackages.legacy_390
    else abort "vexos.gpu.nvidiaDriverVariant: unknown value '${variant}'";
```

Because `lib.types.enum` prevents any value outside the declared set from reaching the
`config` phase, the `else abort` branch can never execute in practice. It may be removed for
cleaner code. Not a blocking issue.

### R2 — Note `legacy_390` kernel compatibility in option description (LOW priority)

The 390.x driver branch is known to require nixpkgs-maintained backport patches to build on
kernels ≥5.16. While `nixos-25.11` includes those patches, users should be aware that `legacy_390`
support has a finite lifespan. A brief note in the option `description` (e.g., *"GeForce 400/500
series; subject to limited kernel support on future kernels"*) would improve user awareness.

### R3 — Document the option in `README.md` (RECOMMENDED per spec Section 5, Step 3)

The spec explicitly lists updating `README.md` as "optional but recommended." The NVIDIA GPU
section of the README should document the `vexos.gpu.nvidiaDriverVariant` option and link to the
per-variant GPU generation examples from the spec. Not required for correctness.

---

## Summary of Findings

The implementation of `modules/gpu/nvidia.nix` is a complete and correct realization of the
specification. All four checklist categories from the review prompt are satisfied:

1. **Option declared correctly** — enum type with four values, default `"latest"`, proper
   `options`/`config` split.
2. **`hardware.nvidia.open = false` for all legacy variants** — enforced via the `useOpen` boolean
   derived solely from `variant == "latest"`.
3. **`nvidia-vaapi-driver` excluded for legacy** — implemented via `lib.mkIf useOpen`.
4. **Backward compatibility** — with default `"latest"`, behavior is byte-for-byte identical to the
   pre-change module.

No CRITICAL issues exist. Three low-priority recommendations are noted but none block approval.
The implementation is safe for use as-is.

---

## Final Verdict

**PASS**

The implementation is approved. No refinement cycle required.
All CRITICAL checks: ✓ clear.
Build validation: not verifiable in this environment (Windows / no Nix CLI in WSL) — treat as
neutral per task instructions; static analysis confirms correctness.
