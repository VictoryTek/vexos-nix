# Review: Remove `gimp-hidden` writeText Derivation from `configuration-stateless.nix`

**Review Date:** 2026-05-15
**Reviewer:** Phase 3 QA (orchestrator review pass)
**Spec:** `.github/docs/subagent_docs/gimp_hidden_spec.md`
**Modified File:** `configuration-stateless.nix`
**Comparison File:** `home-stateless.nix` (unchanged)

---

## 1. Specification Compliance

**Result: PASS**

The spec required exactly two things to be removed and nothing else:

| Spec Requirement | Status |
|-----------------|--------|
| Remove the six-line `# gimp-hidden: a minimal NoDisplay=true …` comment block | ✓ Removed |
| Remove the `(pkgs.writeTextFile { name = "gimp-hidden"; … })` derivation from `environment.systemPackages` | ✓ Removed |
| `pkgs.tor-browser` remains as sole entry in `environment.systemPackages` | ✓ Confirmed present |
| `vexos.flatpak.excludeApps` list is unchanged | ✓ Confirmed unchanged (`"org.gimp.GIMP"` and all five other entries present) |
| No other lines modified | ✓ Confirmed — surrounding context is identical to the spec's "Result After Change" target |

The resulting `environment.systemPackages` block matches the spec verbatim:

```nix
  # ---------- System packages ----------
  # tor-browser: installed system-wide (not via Home Manager) so torbrowser.desktop
  # lands in /run/current-system/sw/share/applications/ and is always visible to
  # GNOME regardless of Home Manager activation timing on the fresh tmpfs home.
  environment.systemPackages = [
    pkgs.tor-browser
  ];
```

---

## 2. Structural Integrity

**Result: PASS**

- `environment.systemPackages = [ pkgs.tor-browser ];` is syntactically well-formed: list is properly opened and closed, semicolon is present after the closing `]`.
- No orphaned commas, semicolons, or unclosed brackets around the removed block.
- The outer `{ … }` of the NixOS module is balanced.
- All section-separator comments (`# ---------- Branding ----------`, `# ---------- Users ----------`, etc.) are intact and in their original positions.

---

## 3. Preservation of Remaining Mechanisms

**Result: PASS — Both remaining mechanisms confirmed**

| Mechanism | Location | Status |
|-----------|----------|--------|
| `vexos.flatpak.excludeApps = [ "org.gimp.GIMP" … ]` | `configuration-stateless.nix` lines 62–71 | ✓ Present and unchanged |
| `xdg.desktopEntries."org.gimp.GIMP" = { name = "GIMP"; noDisplay = true; }` | `home-stateless.nix` lines ~120–123 | ✓ Present and unchanged |

Both mechanisms together are sufficient to prevent GIMP from appearing in the app grid on the stateless role, as detailed in the spec's §3 analysis. Mechanism #3 (excludeApps) uninstalls GIMP from `/persistent/var/lib/flatpak` at `multi-user.target` — before any login is possible. Mechanism #2 (xdg.desktopEntries) covers any residual Flatpak presence at the user XDG layer, which has priority over system and Flatpak-exported paths.

---

## 4. Nothing Else Was Changed

**Result: PASS**

No other modules, imports, options, or files were modified. The change is purely subtractive — dead code removed, nothing added.

- `system.stateVersion = "25.11"` is present and unchanged. ✓
- All `imports = [ … ]` entries are unchanged. ✓
- `vexos.branding.role = "stateless"` is unchanged. ✓
- `vexos.impermanence.enable = true` is unchanged. ✓
- `users.users.nimda.initialPassword = "vexos"` is unchanged. ✓

---

## 5. Build Validation

**Result: DEFERRED TO CI (expected — not a failure)**

Nix is not available on the Windows development machine. Build validation is deferred to GitHub Actions CI (`nix flake check` and `nixos-rebuild dry-build` jobs). This is the documented and expected workflow for Windows-hosted development on this project. No build failure has occurred; the check simply cannot be run locally.

---

## 6. Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 100% | A |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | N/A — Deferred to CI | — |

**Overall Grade: A (100% — excluding deferred build check)**

---

## 7. Summary of Findings

The implementation is a clean, surgical removal of a dead-code derivation. The spec was followed exactly — no more, no less. All preservation requirements are met: `pkgs.tor-browser` remains, `vexos.flatpak.excludeApps` is intact, and the two remaining GIMP-hiding mechanisms in `configuration-stateless.nix` (excludeApps) and `home-stateless.nix` (xdg.desktopEntries noDisplay) are confirmed present and unchanged. The file is syntactically valid. There are no issues to flag.

**Build result:** Deferred to CI (expected on Windows; not a failure)

---

## 8. Verdict

**PASS**
