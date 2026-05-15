# Review: Remove Stale Dock Favourites

**Feature name:** `stale_dock_favourites`  
**Date:** 2026-05-15  
**Phase:** 3 — Review & Quality Assurance  
**Reviewer:** QA Subagent  

---

## 1. Summary

The implementation correctly removes both stale dock-favourite entries as
specified.  Both modified files match the proposed lists in the spec exactly,
with no unintended side-effects, no new `lib.mkIf` guards, and clean Nix
syntax throughout.

**Verdict: PASS**

---

## 2. Specification Compliance

### 2.1 `modules/gnome-htpc.nix`

| Check | Result |
|-------|--------|
| `"system-update.desktop"` absent from `favorite-apps` | ✅ PASS — entry not found in file |
| `"io.github.up.desktop"` still present | ✅ PASS — entry confirmed at expected position |
| Remaining entries in original order | ✅ PASS — exact match with spec §3.3 |
| No new `lib.mkIf` guards | ✅ PASS — only pre-existing guard at line 116 (flatpak service) |
| No other changes to the file | ✅ PASS |

**Final `favorite-apps` list matches spec §3.3 exactly:**

```nix
favorite-apps = [
  "brave-browser.desktop"
  "app.zen_browser.zen.desktop"
  "plex-desktop.desktop"             # nixpkgs plex-desktop package
  "io.freetubeapp.FreeTube.desktop"
  "org.gnome.Nautilus.desktop"
  "io.github.up.desktop"
  "com.mitchellh.ghostty.desktop"
];
```

### 2.2 `modules/gnome-desktop.nix`

| Check | Result |
|-------|--------|
| `"virtualbox.desktop"` absent from `favorite-apps` | ✅ PASS — entry not found in file |
| Remaining entries in original order | ✅ PASS — exact match with spec §4.3 |
| No new `lib.mkIf` guards | ✅ PASS — only pre-existing guard at line 160 (flatpak service) |
| No other changes to the file | ✅ PASS |

**Final `favorite-apps` list matches spec §4.3 exactly:**

```nix
favorite-apps = [
  "brave-browser.desktop"
  "app.zen_browser.zen.desktop"
  "org.gnome.Nautilus.desktop"
  "com.mitchellh.ghostty.desktop"
  "io.github.up.desktop"
  "org.gnome.Boxes.desktop"
  "code.desktop"
];
```

### 2.3 `modules/virtualization.nix` (context confirmation)

`virtualisation.virtualbox.host.enable` is confirmed commented-out with an
explanatory comment (kernel 7.0 incompatibility). This validates the spec's
rationale for removing `virtualbox.desktop` from the desktop dock.

---

## 3. Code Quality

- **Indentation:** Consistent 2-space offset for list items within the
  `favorite-apps` list; matches surrounding file style in both files.
- **Nix list syntax:** Lists are properly opened and closed with `[` / `]`;
  no trailing commas (Nix uses whitespace-separated items, not comma-separated).
- **No blank lines left behind:** The removed entries left no orphan blank lines.
- **Comments preserved:** The `# nixpkgs plex-desktop package` inline comment
  on `plex-desktop.desktop` is intact in `gnome-htpc.nix`.

---

## 4. Build Validation

> **nix flake check deferred to CI — nix unavailable on Windows host.**

Static file validation confirms:
- Both files are syntactically valid Nix attribute sets (no unclosed brackets,
  no mismatched strings, no orphaned commas).
- The `lib.mkIf` references in both files are pre-existing (flatpak-install
  service) and were not touched by this change.

---

## 5. Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 100% | A |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | N/A (deferred to CI) | — |

**Overall Grade: A (100% — static checks)**

---

## 6. Issues

None. No critical issues, no recommended improvements, no informational notes.

---

## 7. Final Verdict

**PASS**

All specification requirements met. Implementation is minimal, clean, and
correct. Ready for preflight validation.
