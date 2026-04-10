# Review: Fix disko / hardware-configuration.nix fileSystems Device Conflict

**Feature name:** `privacy_vm_disko_conflict`
**Date:** 2026-04-10
**Reviewer role:** Subagent Review Phase
**Spec:** `.github/docs/subagent_docs/privacy_vm_disko_conflict_spec.md`
**Modified file:** `modules/privacy-disk.nix`

---

## Score Table

| Category                  | Score | Grade |
|---------------------------|-------|-------|
| Specification Compliance  | 98%   | A+    |
| Best Practices            | 97%   | A+    |
| Functionality             | 100%  | A+    |
| Code Quality              | 97%   | A+    |
| Security                  | 100%  | A+    |
| Performance               | 100%  | A+    |
| Consistency               | 99%   | A+    |
| Build Success             | N/A   | —     |

**Overall Grade: A+ (98.8%) — PASS**

> Note: Build Success is marked N/A because this is a static review conducted
> on Windows where `nix flake check` and `nixos-rebuild dry-build` cannot be
> run. All static, logical, and syntactic checks pass with no issues found.

---

## Detailed Checklist

### Spec Compliance

- [x] `fileSystems."/boot".device = lib.mkForce "/dev/disk/by-partlabel/disk-main-ESP"` is present inside `config = lib.mkIf cfg.enable`
- [x] `fileSystems."/nix".device = lib.mkForce (if cfg.enableLuks then "/dev/mapper/${cfg.luksName}" else "/dev/disk/by-partlabel/disk-main-data")` is present
- [x] `fileSystems."/persistent".device = lib.mkForce (if ... then ... else ...)` is present with identical LUKS/non-LUKS logic
- [x] All three new lines are WITHIN `config = lib.mkIf cfg.enable { }` — confirmed by the file structure (they follow the disko.devices block closing brace, still inside the outer config block, before the final `};` and `}`)
- [x] No other files were modified beyond `modules/privacy-disk.nix`

Minor cosmetic delta from spec: the comment block uses slightly fewer words than
the spec's template (the full "lib.mkForce sets priority 50, which defeats the
default priority-100 definitions emitted by nixos-generate-config without
affecting any user-level mkForce / mkOverride declarations" explanation is
condensed). This is non-functional and not a defect.

---

### Logic Correctness

- [x] `lib.mkForce` sets priority 50 (lower numeric = higher precedence than the default 100) — will resolve all three-way conflicts
- [x] Three-way merge analysis verified:
  - `hardware-configuration.nix` defines each `.device` at priority 100
  - disko module defines each `.device` at priority 100
  - `privacy-disk.nix` overrides each `.device` at priority 50 via `lib.mkForce`
  - NixOS module system discards ALL priority-100 definitions when a priority-50 definition exists; no conflict error is raised; the `lib.mkForce` value wins
- [x] `/boot` partlabel `disk-main-ESP` matches partition name `ESP` on disk `main` — disko generates partlabels as `disk-<diskName>-<partName>` → `disk-main-ESP` ✓
- [x] `/nix` and `/persistent` non-LUKS device `disk-main-data` matches partition name `data` on disk `main` → `disk-main-data` ✓
- [x] LUKS device path interpolates `cfg.luksName` (defaults to `"cryptroot"`, in scope inside `lib.mkIf cfg.enable`) ✓
- [x] `lib.mkForce` on `.device` does NOT disturb `.neededForBoot` — they are separate scalar attributes, each merged independently
- [x] `fileSystems."/persistent".neededForBoot = lib.mkForce true` still present (line ~158)
- [x] `fileSystems."/nix".neededForBoot = lib.mkForce true` still present (line ~159)

---

### Nix Syntax

- [x] String interpolation `"/dev/mapper/${cfg.luksName}"` uses Nix `${}` syntax correctly inside a double-quoted string
- [x] `if cfg.enableLuks then ... else ...` is a valid Nix expression; both branches evaluate to a string — no type mismatch
- [x] All three new attribute assignments terminate with `;` ✓
- [x] Indentation is 4 spaces, consistent with the rest of the file ✓
- [x] The multi-line `if...then...else` expression is correctly wrapped in parentheses for the value position of the attribute assignment ✓

---

### Files That Should NOT Have Changed

- [x] **`flake.nix`** — `privacyBase` module:
  - imports `./modules/privacy-disk.nix` ✓
  - imports `disko.nixosModules.disko` and `impermanence.nixosModules.impermanence` ✓
  - sets `vexos.privacy.disk.enable = true` ✓
  - `privacyGpuVm` module exists and sets `device = lib.mkForce "/dev/vda"` and `enableLuks = lib.mkForce false` ✓
- [x] **`template/etc-nixos-flake.nix`** — uses `vexos-nix.nixosModules.privacyGpuVm` for `vexos-privacy-vm` ✓
- [x] **`hosts/privacy-vm.nix`** — unchanged; imports `../modules/privacy-disk.nix` directly, sets `enableLuks = false`, `device = "/dev/vda"` ✓
- [x] **`modules/impermanence.nix`** — unchanged; `neededForBoot` assertion for `cfg.persistentPath` is still present and still satisfied by `privacy-disk.nix`

---

### Static File Checks

- [x] `modules/gpu/vm.nix` exists ✓
- [x] `modules/privacy-disk.nix` contains all three new `lib.mkForce` device lines ✓
- [x] All referenced files (`configuration-privacy.nix`, `modules/privacy-disk.nix`, `modules/gpu/vm.nix`, `home.nix`) exist in the repository ✓

---

## CRITICAL Issues

**None.**

---

## Observations (Non-Blocking)

1. **Comment brevity:** The comment added above the three new lines is correct but slightly less informative than the spec template. The phrase "lib.mkForce sets priority 50, which defeats the default priority-100 definitions emitted by nixos-generate-config without affecting any user-level mkForce / mkOverride declarations" was condensed to a two-line summary. No functional impact; the intent is still clear.

2. **Impermanence assertion alignment:** The `impermanence.nix` assertion checks `fileSystems."${cfg.persistentPath}".neededForBoot or false`. With the new `.device` mkForce, the `fileSystems."/persistent"` attribute set will now have both `.neededForBoot` (mkForce true) and `.device` (mkForce partlabel/mapper) populated by `privacy-disk.nix` and the disko module respectively. The assertion evaluates `.neededForBoot` only, so it remains satisfied. ✓

---

## Summary

The implementation is a minimal, correct, and well-scoped change. Exactly three
lines were added to `modules/privacy-disk.nix` inside the `config = lib.mkIf
cfg.enable { }` block. Each line uses `lib.mkForce` to assert the correct
device path for `/boot`, `/nix`, and `/persistent`, ensuring that disko's
partlabel/mapper-based declarations win over any conflicting UUID-based entries
in `hardware-configuration.nix` generated without the `--no-filesystems` flag.
The LUKS/non-LUKS branching logic is correct, the partition label values match
the disko layout, and all pre-existing `neededForBoot` overrides remain intact.
No regressions detected in any other file.

**Result: PASS**
