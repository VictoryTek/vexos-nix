# Brave Origin Dock & Default Browser Swap — Phase 3 Review

**Spec:** `brave_origin_dock_swap_spec.md`
**Implementation commit:** `c17a102`

---

## Files Reviewed

- `modules/gnome-desktop.nix`
- `home/gnome-common.nix`
- `home/gnome-common-desktop.nix` (new)
- `home-desktop.nix`

---

## Review Findings

### 1. Specification Compliance — PASS

All four implementation steps executed exactly per spec:

| Step | Spec requirement | Status |
|------|-----------------|--------|
| 1 | `gnome-desktop.nix`: `brave-browser.desktop` → `brave-origin.desktop` in `favorite-apps` | ✅ Done (line 25) |
| 2 | `home/gnome-common.nix`: remove `xdg.mimeApps` block | ✅ Done (file now ends at line 57) |
| 3 | New `home/gnome-common-desktop.nix` with `brave-origin.desktop` MIME defaults | ✅ Done |
| 4 | `home-desktop.nix`: add `./home/gnome-common-desktop.nix` to imports | ✅ Done (line 11) |

### 2. Best Practices — PASS

- `home/gnome-common-desktop.nix` uses `{ ... }:` argument form, consistent with all other `home/` sub-modules.
- `xdg.mimeApps.enable = true` is set alongside `defaultApplications`, which is required by Home Manager.
- `xdg.configFile."mimeapps.list".force = true` and `xdg.dataFile."applications/mimeapps.list".force = true` are both present — this correctly prevents activation stalls when GNOME has already written these files.
- List syntax (`[ "brave-origin.desktop" ]`) is used for `defaultApplications` values — semantically identical to bare string, consistent with the prior implementation in `gnome-common.nix`.

### 3. Consistency — PASS

- `home/gnome-common.nix` remains role-agnostic with no `lib.mkIf` guards — unchanged except the MIME block deletion.
- `home/gnome-common-desktop.nix` is a pure addition file with no conditional logic inside, exactly per Option B.
- It is imported exclusively from `home-desktop.nix` — no other role imports it.
- Naming convention (`gnome-common-desktop.nix` = base `gnome-common` + qualifier `desktop`) matches the established pattern.

### 4. Maintainability — PASS

- New file has a clear header comment explaining its purpose and the reason for the split.
- The MIME block comment explains the `force = true` rationale.
- Scope of the trade-off (htpc/stateless/server losing declarative MIME registration) is documented in the spec and was explicitly accepted.

### 5. Completeness — PASS

Both user objectives are addressed:
- Dock favorite: `brave-origin.desktop` is now the first entry in `favorite-apps`.
- Default browser: `brave-origin.desktop` is registered as the XDG MIME default for all five web schemes, desktop-role only.

### 6. Performance — PASS

No regressions. One new small Home Manager module evaluated at activation; negligible overhead.

### 7. Security — PASS

- No secrets, no hardcoded credentials, no world-writable paths.
- `force = true` on mimeapps.list is standard Home Manager practice; no security implication.

### 8. API Currency — PASS

`xdg.mimeApps` is the current Home Manager option for MIME associations. No deprecated paths used.

### 9. Build Validation

| Check | Result |
|-------|--------|
| `nix flake show --impure` | ✅ PASS — all outputs listed, no errors |
| `vexos-desktop-amd` `nix eval …drvPath` | ✅ PASS — `/nix/store/1rns06n50f…drv` |
| `vexos-desktop-nvidia` `nix eval …drvPath` | ✅ PASS — `/nix/store/lrr8p63hqs…drv` |
| `vexos-desktop-vm` `nix eval …drvPath` | ✅ PASS — `/nix/store/ncy76kjzpl…drv` |
| `git ls-files hardware-configuration.nix` | ✅ PASS — empty (not tracked) |
| `system.stateVersion` unchanged | ✅ PASS — all six configs remain at `"25.11"` |
| All new flake inputs declare `follows` | N/A — no new flake inputs |

> Note: `sudo nixos-rebuild dry-build` is blocked in this container environment (no-new-privileges flag). Replaced with `nix eval --impure "…drvPath"` per CLAUDE.md, which forces full evaluation to the same depth as `--no-build`.

---

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A+ |
| Best Practices | 100% | A+ |
| Functionality | 100% | A+ |
| Code Quality | 100% | A+ |
| Security | 100% | A+ |
| Performance | 100% | A+ |
| Consistency | 100% | A+ |
| Build Success | 100% | A+ |

**Overall Grade: A+ (100%)**

---

## Verdict: PASS
