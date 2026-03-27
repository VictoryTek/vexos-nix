# Review: CachyOS Pre-built Kernel — Binary Cache Fix

**Date:** 2026-03-27  
**Reviewer:** NixOS Review Agent  
**Spec:** `.github/docs/subagent_docs/cachyos_prebuilt_kernel_spec.md`  
**Files Reviewed:** `flake.nix`, `template/etc-nixos-flake.nix`, `configuration.nix`

---

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 95% | A |
| Best Practices | 97% | A+ |
| Functionality | 100% | A+ |
| Code Quality | 92% | A |
| Security | 100% | A+ |
| Consistency | 90% | A- |

**Overall Grade: A (96%)**

---

## Validation Checklist Results

| # | Check | File | Result |
|---|-------|------|--------|
| 1 | `nixConfig` block present in `flake.nix` before `inputs` | `flake.nix` | ✅ PASS |
| 2 | `nixConfig.extra-substituters` correct in `flake.nix` | `flake.nix` | ✅ PASS |
| 3 | `nixConfig.extra-trusted-public-keys` correct in `flake.nix` | `flake.nix` | ✅ PASS |
| 4 | `nixConfig` appears before `description` and `inputs` | `flake.nix` | ✅ PASS |
| 5 | `cachyosOverlayModule` uses `overlays.pinned` | `flake.nix` | ✅ PASS |
| 6 | `nixosModules.base` inline overlay uses `overlays.pinned` | `flake.nix` | ✅ PASS |
| 7 | Zero occurrences of `overlays.default` in `flake.nix` | `flake.nix` | ✅ PASS |
| 8 | Zero occurrences of `overlays.default` in template | `template/etc-nixos-flake.nix` | ✅ PASS |
| 9 | `nixConfig` block present in template before `inputs` | `template/etc-nixos-flake.nix` | ✅ PASS |
| 10 | Template `nixConfig` caches/keys match `flake.nix` | `template/etc-nixos-flake.nix` | ✅ PASS |
| 11 | Initial install commands include `--accept-flake-config` (all 4 variants) | `template/etc-nixos-flake.nix` | ✅ PASS |
| 12 | Manual rebuild command includes `--accept-flake-config` | `template/etc-nixos-flake.nix` | ✅ PASS |
| 13 | Variant-switching command includes `--accept-flake-config` | `template/etc-nixos-flake.nix` | ⚠️ MISSING |
| 14 | Nix syntax valid — semicolons, braces, list formatting | `flake.nix` | ✅ PASS |
| 15 | Nix syntax valid — semicolons, braces, list formatting | `template/etc-nixos-flake.nix` | ✅ PASS |
| 16 | No unintended changes — existing comments and code preserved | all | ✅ PASS |
| 17 | `nix.settings.substituters` in `configuration.nix` unchanged | `configuration.nix` | ✅ PASS |
| 18 | `system.stateVersion` not modified | `configuration.nix` | ✅ PASS |
| 19 | `hardware-configuration.nix` not present in repo | repo root | ✅ PASS |

---

## Detailed Findings

### ✅ Check 1–4 — `nixConfig` in `flake.nix`

The `nixConfig` block is correctly placed as the **first attribute** in the top-level attribute set, before `description` and before `inputs`. Both caches and both keys are present and match the upstream values from the spec verbatim.

```
extra-substituters:
  https://attic.xuyh0120.win/lantian  ← Primary Hydra CI cache ✅
  https://cache.garnix.io             ← Fallback Garnix cache  ✅

extra-trusted-public-keys:
  lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc=        ✅
  cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g= ✅
```

---

### ✅ Check 5–8 — `overlays.pinned` in both application sites

`grep` over the entire workspace against `overlays\.default` returned **zero hits** in any tracked `.nix` file. All hits were confined to documentation files (spec files, old reviews) in `.github/docs/subagent_docs/` — expected and correct.

Both application sites have been correctly updated:

**Site 1 — `cachyosOverlayModule` (direct builds):**
```nix
cachyosOverlayModule = {
  nixpkgs.overlays = [ nix-cachyos-kernel.overlays.pinned ];   ← ✅
};
```

**Site 2 — `nixosModules.base` (template/module-consumer path):**
```nix
nixpkgs.overlays = [
  nix-cachyos-kernel.overlays.pinned   ← ✅
  (final: prev: { unstable = ...; })
];
```

This resolves Root Cause 1 (derivation hash mismatch) for all four build targets and for the module consumer path used by `template/etc-nixos-flake.nix`.

---

### ✅ Check 9–12 — `nixConfig` and `--accept-flake-config` in template

The `nixConfig` block in `template/etc-nixos-flake.nix` is correctly placed immediately after the opening `{` of the file, before `inputs`, and contains identical cache entries to `flake.nix`. This is correct per spec because `nixConfig` does not propagate through flake inputs — it must be present in the **top-level** flake being built, which for fresh installs is `/etc/nixos/flake.nix`.

All four initial install commands and the manual rebuild command correctly include `--accept-flake-config`:
```
sudo nixos-rebuild switch --flake /etc/nixos#vexos-amd    --accept-flake-config  ✅
sudo nixos-rebuild switch --flake /etc/nixos#vexos-nvidia --accept-flake-config  ✅
sudo nixos-rebuild switch --flake /etc/nixos#vexos-intel  --accept-flake-config  ✅
sudo nixos-rebuild switch --flake /etc/nixos#vexos-vm     --accept-flake-config  ✅
sudo nixos-rebuild switch --flake /etc/nixos#$(cat /etc/nixos/vexos-variant) --accept-flake-config  ✅
```

---

### ⚠️ Check 13 — Variant-switching command missing `--accept-flake-config` (RECOMMENDED)

The "Switching to a different variant later" comment section at [template/etc-nixos-flake.nix](template/etc-nixos-flake.nix#L29-L35) reads:

```
# ── Switching to a different variant later (e.g. vm → amd) ──────────────────
#
#   Just rebuild with the new variant target:
#     sudo nixos-rebuild switch --flake /etc/nixos#vexos-amd   ← missing --accept-flake-config
#   /etc/nixos/vexos-variant is updated automatically...
```

When a user switches variants, `nixConfig` is still required to trust the CachyOS caches (Nix cache trust is per command invocation, not permanently stored). Without `--accept-flake-config`, nix will prompt the user interactively to accept the caches, or silently skip them if running in a non-interactive context. This is inconsistent with the rest of the template's instructions and may surprise users who switch variants after initial setup.

**Note:** This case was not explicitly listed in the spec's implementation steps, so this is a gap rather than a spec deviation.

**Recommended fix:**
```
#     sudo nixos-rebuild switch --flake /etc/nixos#vexos-amd --accept-flake-config
```

---

### ✅ Check 14–15 — Nix syntax validity

Both files were manually traced for syntax correctness:

- All attribute set values are terminated with `;`
- All attribute sets `{ }` are properly balanced and closed
- List literals use whitespace-separated elements (no erroneous commas — correct for Nix)
- Lambda expressions `(final: prev: { ... })` are correctly formed
- String interpolation `"${variant}\n"` in the template is syntactically valid
- No trailing commas anywhere
- `inherit` forms are correct (`inherit (final) config;`, `inherit inputs;`)
- The top-level attribute set in both files is balanced end-to-end

---

### ✅ Check 16 — No unintended changes

Comparison against expected pre-implementation state confirms:
- All existing comments in `flake.nix` are preserved
- The `description`, `inputs`, and `outputs` sections of `flake.nix` are structurally unchanged
- The template header comment block (bootloader instructions, variant documentation) is fully preserved
- No lines were removed from either file except as part of the specified changes

---

### ✅ Check 17–19 — `configuration.nix` untouched

`configuration.nix` was not part of the spec's implementation scope, and correctly was not modified. The `nix.settings.substituters` block is intact with all four caches, `system.stateVersion = "25.11"` is present, and `hardware-configuration.nix` is not in the repository.

---

### INFORMATIONAL — Comment in `cachyosOverlayModule` not present

The spec's Step 2 suggested adding an explanatory comment to `cachyosOverlayModule`:

```nix
cachyosOverlayModule = {
  # overlays.pinned uses nix-cachyos-kernel's internally pinned nixpkgs revision,
  # guaranteeing the derivation hash matches what CI built and cached.
  nixpkgs.overlays = [ nix-cachyos-kernel.overlays.pinned ];
};
```

The implementation omits this comment. The code remains correct and self-consistent — the absence of the comment does not affect functionality. However, the comment would make the `pinned` vs `default` distinction explicit for future maintainers.

### INFORMATIONAL — Explanatory comment above `nixConfig` in template not present

The spec's section 5.2 suggested prefacing the template's `nixConfig` block with a comment explaining its purpose. The implementation omits this. Not a functional issue.

---

## Summary

The implementation correctly addresses both root causes identified in the specification:

- **Root Cause 1 (derivation hash mismatch):** Fixed by replacing `overlays.default` with `overlays.pinned` at both application sites in `flake.nix`. Confirmed zero occurrences of `.overlays.default` remain in any tracked `.nix` file.

- **Root Cause 2 (bootstrapping gap):** Fixed by adding a `nixConfig` block to both `flake.nix` and `template/etc-nixos-flake.nix`, and updating rebuild command examples to include `--accept-flake-config`.

`configuration.nix` was correctly left unmodified. Nix syntax is valid in both files. No unintended changes were introduced.

**One RECOMMENDED issue** was identified: the variant-switching command example in the template header is missing `--accept-flake-config`, inconsistent with all other rebuild examples in the same file.

**Two INFORMATIONAL items** were noted regarding optional comments that were described in the spec examples but not carried through to the implementation.

---

## Verdict

**PASS**

The implementation is functionally correct and fully resolves the CachyOS prebuilt kernel compilation problem. The single RECOMMENDED issue (missing `--accept-flake-config` in the variant-switching comment) is a documentation gap that would not cause build failures — it would only surface as an interactive prompt (or silent degradation) for users who switch GPU variants after initial setup. It does not block release.
