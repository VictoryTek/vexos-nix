# Review: Remove Duplicate dconf Power Keys from `gnome-htpc.nix`

**Feature name:** `htpc_dconf_power`  
**Review type:** Post-implementation QA  
**Reviewer:** Review Subagent  
**Date:** 2026-05-15  

---

## Verdict: PASS

All specification requirements are satisfied. The change is a clean, surgical
deletion with no collateral damage, no regressions, and no architecture
violations. Static analysis confirms the implementation is correct.

---

## 1. Specification Compliance

### ✅ `"org/gnome/settings-daemon/plugins/power"` block absent from `gnome-htpc.nix`

The block described in the spec (spec §1) is **not present** in the current
`modules/gnome-htpc.nix`. The `programs.dconf.profiles.user.databases` list
contains exactly one entry with the following dconf paths — none of which is
`org/gnome/settings-daemon/plugins/power`:

- `org/gnome/desktop/interface` (accent-color)
- `org/gnome/shell` (enabled-extensions, favorite-apps)
- `org/gnome/shell/extensions/dash-to-dock`
- `org/gnome/desktop/app-folders`
- `org/gnome/desktop/app-folders/folders/Office`
- `org/gnome/desktop/app-folders/folders/Utilities`
- `org/gnome/desktop/app-folders/folders/System`

The duplicate block has been completely and correctly removed.

### ✅ `sleep-inactive-ac-type` and `sleep-inactive-battery-type` present in `system-nosleep.nix`

Verified at lines 56–57 of `modules/system-nosleep.nix`:

```nix
sleep-inactive-ac-type         = "nothing";
sleep-inactive-battery-type    = "nothing";
```

All five power keys (`sleep-inactive-ac-type`, `sleep-inactive-battery-type`,
`sleep-inactive-ac-timeout`, `sleep-inactive-battery-timeout`,
`power-button-action`) are present and set correctly.

### ✅ `system-nosleep.nix` left unchanged

The file matches the canonical content described in spec §3. No edits were made.

---

## 2. No Collateral Damage

### ✅ All other dconf keys intact

All seven dconf settings paths that should be in `gnome-htpc.nix` are present
and unmodified. No keys were accidentally removed or altered during the deletion.

### ✅ Nix syntax is valid

Manual structural inspection of the complete file confirms:
- The `programs.dconf.profiles.user.databases` list is properly opened and closed.
- No dangling commas after the last entry.
- The outer `{ ... }` attribute set is properly closed (verified at the final
  line of the file).
- The `let ... in` block is syntactically complete.
- The `systemd.services.flatpak-install-gnome-apps` block is unaffected.

---

## 3. Architecture Pattern Compliance

### ✅ No new `lib.mkIf` guards added

The change is a pure deletion. No conditional logic was introduced.

### ✅ Only a deletion — no new content

No new files, no new options, no new imports. The scope of the change is exactly
what the spec prescribes.

---

## 4. Behavioural Correctness

### ✅ `configuration-htpc.nix` imports both files

Verified in `configuration-htpc.nix`:

| Import | Line |
|--------|------|
| `./modules/gnome-htpc.nix` | 5 |
| `./modules/system-nosleep.nix` | 17 |

Both modules are imported into the HTPC configuration.

### ✅ `system-nosleep.nix` is the sole setter — no regression

Before the fix: `gnome-htpc.nix` silently overrode the `system-nosleep` values
for `sleep-inactive-ac-type` and `sleep-inactive-battery-type` because the htpc
database appeared later in the merged list (per dconf merge semantics, last
entry wins). Although both set `"nothing"`, the override was semantically
incorrect — a protective "never sleep" module was being overridden by a role
display module.

After the fix: `system-nosleep.nix` uses `lib.mkBefore` to insert its database
at the front of the list, and no other module sets any keys under
`org/gnome/settings-daemon/plugins/power`. The canonical setter now controls
all five keys without interference. The observable behaviour is identical (both
set `"nothing"`), but the correctness of the precedence chain is restored.

---

## 5. Build Validation

`nix` is not available on this Windows host. Full `nix flake check` and
`nixos-rebuild dry-build` could not be executed.

Static checks performed instead:

| Check | Result |
|-------|--------|
| `hardware-configuration.nix` tracked in git | ❌ Not tracked (git ls-files returned empty) ✅ |
| `system.stateVersion` present in `configuration-htpc.nix` | ✅ `"25.11"` — unchanged |
| `system.stateVersion` present in `configuration-desktop.nix` | Not re-checked (out of scope for this change) |
| Nix syntax structural integrity | ✅ Pass (manual inspection) |
| No new flake inputs introduced | ✅ Pure deletion, no inputs changed |
| `gnome-htpc.nix` import chain intact | ✅ Imports `./gnome.nix` as before |

**Build validation note:** Because this change is a pure deletion of an
attribute set literal containing only string values with no references to
external packages, variables, or options, there is negligible risk of a
build regression. The remaining content of `gnome-htpc.nix` is identical to
its pre-change state.

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
| Build Success | N/A* | — |

*Build not executed: `nix` unavailable on Windows host. All static checks pass.
Risk of build failure assessed as negligible (pure literal deletion).

**Overall Grade: A (100% on all verifiable categories)**

---

## Summary

The implementation is correct and complete. The `"org/gnome/settings-daemon/plugins/power"`
block has been cleanly removed from `modules/gnome-htpc.nix` with no syntax
errors, no collateral damage, and no architecture violations. `system-nosleep.nix`
remains intact as the sole authoritative setter of all five power management
dconf keys for all roles that import it — including the HTPC role, which imports
it via `configuration-htpc.nix`. `hardware-configuration.nix` is not tracked in
git, and `system.stateVersion` is present and unchanged.

**Build result:** Static checks PASS — live `nix flake check` not executable on Windows host.  
**Verdict: PASS**
