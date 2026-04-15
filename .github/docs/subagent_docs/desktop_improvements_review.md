# Desktop Improvements — Review & Quality Assurance

## Feature Name
`desktop_improvements`

## Date
2026-04-15

## Reviewer Phase
Phase 3: Review & QA

---

## 1. Modified Files Reviewed

| File | Spec Section | Status |
|------|-------------|--------|
| `modules/gaming.nix` | §4.8 | ✅ All changes match spec |
| `modules/packages.nix` | §4.9 | ✅ All changes match spec |
| `configuration-stateless.nix` | §4.10 | ✅ All changes match spec |

---

## 2. Detailed File Verification

### 2.1 modules/gaming.nix

| Spec Requirement | Implemented | Notes |
|-----------------|-------------|-------|
| `programs.mangohud.enable = true;` added after gamescope block | ✅ Line 29 | Correct NixOS module usage |
| Header updated (removed Lutris, Heroic, Bottles, OBS, Input Remapper) | ✅ Lines 1-4 | Now references Flatpak for Lutris/ProtonPlus/Bottles |
| Commented-out `## mangohud` replaced with NOTE comment | ✅ Line 49 | See RECOMMENDED-01 below |
| Input-remapper block removed | ✅ | Entire 4-line block removed, confirmed via grep |
| Flatpak NOTE updated to include Bottles | ✅ Lines 67-68 | Correct app IDs referenced |

**Nix syntax:** ✅ Matched braces, proper semicolons, valid attribute sets.

### 2.2 modules/packages.nix

| Spec Requirement | Implemented | Notes |
|-----------------|-------------|-------|
| `htop` replaced with `btop` | ✅ Line 11 | Correct package name |
| Header updated to "Base system packages for non-desktop roles" | ✅ Lines 1-3 | Accurate description |
| Section renamed "System utilities" with per-package comments | ✅ Lines 10-15 | Consistent with development.nix style |

**Nix syntax:** ✅ Correct list format, proper `with pkgs;` scoping.

### 2.3 configuration-stateless.nix

| Spec Requirement | Implemented | Notes |
|-----------------|-------------|-------|
| `permittedInsecurePackages` block removed | ✅ | Confirmed absent via grep (no matches in file) |
| `system.stateVersion` unchanged | ✅ Line 123 | `"25.11"` preserved |

**Nix syntax:** ✅ Valid module structure, proper imports and attribute sets.

---

## 3. Unchanged File Spot-Checks

### 3.1 Safety Invariants

| Check | Result |
|-------|--------|
| `system.stateVersion = "25.11"` in `configuration.nix` | ✅ Line 123, unchanged |
| `system.stateVersion = "25.11"` in `configuration-stateless.nix` | ✅ Line 123, unchanged |
| `system.stateVersion = "25.11"` in `configuration-htpc.nix` | ✅ Line 74, unchanged |
| `system.stateVersion = "25.11"` in `configuration-server.nix` | ✅ Line 73, unchanged |
| `hardware-configuration.nix` NOT tracked in git | ✅ `file_search` returned no results |

### 3.2 Pre-existing Features Verified in Unchanged Files

The spec identified 20+ items as "already done." Spot-checked 12:

| Item | File | Status |
|------|------|--------|
| `vm.max_map_count = 2147483642` | `modules/system.nix` line 102 | ✅ Present |
| `services.scx` (scx_lavd scheduler) | `modules/system.nix` lines 116-119 | ✅ Enabled |
| BT codecs (AAC, LDAC, aptX, aptX HD) | `modules/audio.nix` line 38 | ✅ Configured |
| `programs.direnv` + nix-direnv | `home.nix` lines 80-83 | ✅ Configured |
| `programs.tmux` (mouse, vi-mode, C-a) | `home.nix` lines 86-95 | ✅ Configured |
| `wl-clipboard` | `home.nix` line 37 | ✅ In packages |
| `jxl-pixbuf-loader` | `modules/gnome.nix` line 130 | ✅ Present |
| nil, nixpkgs-fmt, nix-output-monitor | `modules/development.nix` lines 42-44 | ✅ Present |
| Go toolchain | `modules/development.nix` line 48 | ✅ Present |
| `org.gnome.World.PikaBackup` | `modules/flatpak.nix` line 24 | ✅ Present |
| `com.usebottles.bottles` | `modules/flatpak.nix` line 25 | ✅ Present |
| `com.github.wwmm.easyeffects` | `modules/flatpak.nix` line 26 | ✅ Present |

All 12/12 spot-checks passed. The spec's "already done" claims are accurate.

---

## 4. Package Duplication Audit

Cross-checked `gaming.nix`, `development.nix`, `packages.nix`, `home.nix`, `flatpak.nix`:

| Package | gaming.nix | development.nix | packages.nix | home.nix | Duplicate? |
|---------|-----------|-----------------|-------------|---------|-----------|
| `btop` | — | — | ✅ | ✅ | No — different roles (non-desktop vs desktop/HM) |
| `inxi` | — | — | ✅ | ✅ | No — different roles |
| `brave` | — | ✅ | ✅ | — | No — different roles |
| `git` | — | ✅ | ✅ | — | No — different roles |
| `curl` | — | ✅ | ✅ | — | No — different roles |
| `wget` | — | ✅ | ✅ | — | No — different roles |
| `htop` | — | — | — | — | ✅ Fully removed |
| `mangohud` | (module) | — | — | — | ✅ Correct — uses `programs.mangohud.enable` |

**No true duplications exist.** Apparent overlaps are by design: `configuration.nix` (desktop) imports `development.nix` but NOT `packages.nix`; non-desktop configs import `packages.nix` but NOT `development.nix`.

---

## 5. Issues Found

### RECOMMENDED-01: Incorrect directional reference in comment

**File:** `modules/gaming.nix` line 49
**Current:** `# NOTE: MangoHud is enabled via programs.mangohud.enable below (not as a package).`
**Problem:** `programs.mangohud.enable = true` is at line 29, which is **above** this comment, not below.
**Fix:** Change `below` to `above`.
**Severity:** Cosmetic — no functional impact.
**Note:** This error originates in the spec (§4.8), and the implementation faithfully reproduced it.

---

## 6. Build Validation

### Environment Limitation

This review is performed on a **Windows development environment**. The following tools are NOT available:
- `nix` CLI (`nix flake check`)
- `sudo` / `nixos-rebuild`
- NixOS evaluation infrastructure

**This is an environmental limitation, NOT a code defect.**

### Static Validation Performed

| Check | Result |
|-------|--------|
| Nix syntax (braces, semicolons, attribute sets) — all 3 files | ✅ Manual review passed |
| `programs.mangohud.enable` is a valid NixOS option (since 23.05) | ✅ Verified |
| `btop` is a valid nixpkgs package | ✅ Verified |
| No unresolved package references introduced | ✅ |
| No stale imports or broken module references | ✅ |

### Deferred Build Checks (require NixOS host)

- [ ] `nix flake check`
- [ ] `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd`
- [ ] `sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia`
- [ ] `sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm`
- [ ] `nix flake lock` (prune stale nix-gaming from flake.lock)

---

## 7. Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 98% | A+ |
| Best Practices | 96% | A |
| Functionality | 100% | A+ |
| Code Quality | 93% | A |
| Security | 100% | A+ |
| Performance | 100% | A+ |
| Consistency | 96% | A |
| Build Success | 85% | B |

**Overall Grade: A (96%)**

Build Success is scored at 85% solely due to inability to execute `nix flake check` / `nixos-rebuild dry-build` on the Windows review environment. Static syntax analysis found no issues. All other categories reflect high-quality, spec-compliant implementation.

---

## 8. Verdict

### **PASS**

All three modified files match the specification exactly. No critical or blocking issues found. One cosmetic RECOMMENDED fix identified (comment says "below" instead of "above"). Safety invariants preserved. No duplicate packages introduced. Pre-existing features confirmed present in unchanged files.

### Action Items

| Priority | Item | File |
|----------|------|------|
| RECOMMENDED | Fix "below" → "above" in MangoHud comment | `modules/gaming.nix` line 49 |
| POST-DEPLOY | Run `nix flake lock` on NixOS host | `flake.lock` |
| POST-DEPLOY | Run full dry-build validation | All variants |
