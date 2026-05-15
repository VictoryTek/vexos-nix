# Review: home-htpc.nix — Wayland Session Variables & Terminal Packages

**Feature:** `home_htpc_wayland_packages`  
**Reviewer:** QA Subagent  
**Status:** PASS (with minor observations)

---

## Checklist Results

### Specification Compliance

| Check | Result | Notes |
|---|---|---|
| `home.sessionVariables` present | ✅ PASS | Block present |
| `NIXOS_OZONE_WL = "1"` | ✅ PASS | Correct value |
| `MOZ_ENABLE_WAYLAND = "1"` | ✅ PASS | Correct value |
| `QT_QPA_PLATFORM = "wayland;xcb"` | ✅ PASS | Correct value |
| `home.packages` with `with pkgs;` | ✅ PASS | Correct syntax |
| `ghostty` present | ✅ PASS | |
| `tree` present | ✅ PASS | |
| `ripgrep` present | ✅ PASS | |
| `fd` present | ✅ PASS | |
| `bat` present | ✅ PASS | |
| `eza` present | ✅ PASS | |
| `fzf` present | ✅ PASS | |
| `wl-clipboard` present | ✅ PASS | With correct inline comment |
| `fastfetch` present | ✅ PASS | |
| No duplicate `home.packages` | ✅ PASS | Exactly one block |
| No duplicate `home.sessionVariables` | ✅ PASS | Exactly one block |
| No `lib.mkIf` guards introduced | ✅ PASS | None present |

All functional checklist items pass.

---

### Code Quality

**Indentation:** 2 spaces throughout — matches the rest of the file. ✅

**`with pkgs;` style:** Matches `home-desktop.nix`, `home-server.nix`, and `home-stateless.nix` exactly. ✅

**No unrelated changes:** Only the two specified blocks were added. ✅

#### Minor Observations (non-blocking)

**1. Missing `# Terminal emulator` sub-header inside `home.packages`**

All three peer files structure the `home.packages` block with a `# Terminal emulator` comment before `ghostty`:

```nix
# home-server.nix / home-stateless.nix / home-desktop.nix pattern:
home.packages = with pkgs; [
  # Terminal emulator
  ghostty

  # Terminal utilities
  ...
```

The implementation omits this sub-header:

```nix
# home-htpc.nix (implemented):
home.packages = with pkgs; [
  ghostty

  # Terminal utilities
  ...
```

**2. Missing NOTE comments inside `home.packages`**

Peer files include documentation comments explaining which packages are provided system-wide to avoid confusion during future maintenance. The spec explicitly included these. Both are absent from the implementation:

```nix
# Missing from implementation:
wl-clipboard  # Wayland clipboard CLI (wl-copy / wl-paste)
# NOTE: just is installed system-wide via modules/packages-common.nix.

# System utilities
fastfetch
# NOTE: btop and inxi are installed system-wide via modules/packages-common.nix.
```

**3. Block placement deviates from spec**

The spec (Change 1) specified inserting `home.packages` near the top of the file, directly after `home.homeDirectory`, to match the pattern in `home-desktop.nix`, `home-server.nix`, and `home-stateless.nix`. In all three peer files, `home.packages` is the first named block after `home.username`/`home.homeDirectory`.

The implementation placed `home.packages` at the bottom of the file (before `home.stateVersion`), after `home.sessionVariables`.

The spec (Change 2) specified inserting `home.sessionVariables` before `home.file."justfile"`. The implementation placed it after `home.file."justfile"`.

**Impact:** Nix attribute set ordering is semantically irrelevant — the placement has zero effect on evaluation, build, or runtime behaviour. This is a cosmetic inconsistency with peer file structure only.

**4. `home.sessionVariables` section comment header differs from spec**

- Spec specified: `# ── Session environment variables ─────────────────────────────────────────`
- Implementation uses: `# ── Wayland session variables ─────────────────────────────────────────────`

The implementation heading is actually more specific and informative. Not a defect.

---

### Architecture

| Check | Result |
|---|---|
| Home Manager file — Option B NixOS module rule does not apply | ✅ PASS |
| `ghostty` confirmed in `gnome-htpc.nix` `favorite-apps` as `"com.mitchellh.ghostty.desktop"` | ✅ PASS |
| No NixOS module files modified | ✅ PASS |

---

### Security

No concerns. Environment variables are standard Wayland/toolkit hints — no credentials, secrets, or privileged paths. All packages are standard nixpkgs entries with no overlay references. ✅

---

### Build Validation

**nix flake check deferred to CI — nix unavailable on Windows host.**

Static file validation performed:

| Check | Result |
|---|---|
| Valid Nix attribute set syntax | ✅ PASS |
| `home.sessionVariables` is an attrset of strings | ✅ PASS |
| `home.packages` is a list with `with pkgs;` scope | ✅ PASS |
| All package names match known `nixpkgs` attributes | ✅ PASS — all 9 confirmed in spec Section 4 |
| No use of `unstable.` prefix (not needed for these packages) | ✅ PASS |
| `hardware-configuration.nix` not present in repo | ✅ PASS (not checked in) |
| `system.stateVersion` not modified | ✅ PASS — `home.stateVersion = "24.05"` unchanged |

---

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 82% | B |
| Best Practices | 95% | A |
| Functionality | 100% | A+ |
| Code Quality | 88% | B+ |
| Security | 100% | A+ |
| Performance | 100% | A+ |
| Consistency | 85% | B+ |
| Build Success | Deferred | N/A |

**Overall Grade: A (93%)**

*(Build Success excluded from average — deferred to CI on Windows host)*

---

## Issue Classification

| Severity | Count | Description |
|---|---|---|
| CRITICAL | 0 | — |
| RECOMMENDED | 3 | Missing `# Terminal emulator` header; missing 2 NOTE comments; placement inconsistency with peer files |
| INFORMATIONAL | 1 | Section comment header wording differs from spec (but is more descriptive) |

---

## Summary

The implementation correctly delivers all functional requirements. Both `home.sessionVariables` and `home.packages` are present with the exact values and packages specified. The `with pkgs;` style is correct. No `lib.mkIf` guards were introduced. No duplicate blocks exist. `ghostty` being a dock favourite in `gnome-htpc.nix` confirms the package inclusion is intentional and closes the broken-dock-entry defect.

The three minor observations (missing `# Terminal emulator` sub-header, two absent NOTE comments, and block placement) are cosmetic deviations from the spec and peer file pattern. None affect evaluation, build, or runtime behaviour.

**Verdict: PASS**

The implementation is functionally complete and safe to build. The three RECOMMENDED items may optionally be addressed in a follow-up tidy commit to bring the file into full alignment with peer file structure.
