# Review: Remove org.gnome.Calculator and org.gnome.Calendar from Non-Desktop Roles

**Feature:** remove-gnome-apps-non-desktop  
**Reviewer:** QA Subagent  
**Date:** 2026-04-17  
**Files Reviewed:**
- `modules/gnome.nix` (modified)
- `.github/docs/subagent_docs/remove-gnome-apps-non-desktop_spec.md` (spec)

---

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 95% | A |
| Functionality | 95% | A |
| Code Quality | 95% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | N/A | — |

**Overall Grade: A (98% — build validation deferred to CI)**

---

## Build Validation

- **`nix flake check`**: Could not be executed. The Windows host does not have Nix
  installed; WSL (Ubuntu) is present but stopped and Nix is not in its PATH.
  The `scripts/preflight.sh` script's Check 0 confirms this is a known constraint
  for Windows contributors — CI via GitHub Actions validates the flake on every push.
- **`nixos-rebuild dry-build`**: Not executable on Windows host; requires a NixOS
  system or Nix-capable Linux environment.
- **Static code analysis**: No syntax errors identified. All Nix builtins and
  `lib` functions used are stable and correct. Evaluation-time patterns mirror
  existing, tested code in `modules/flatpak.nix`.

**Build result: Unable to run directly — deferred to GitHub Actions CI**

---

## Detailed Findings

### 1. Specification Compliance — 100%

Every implementation detail matches the spec exactly:

| Spec Requirement | Status |
|-----------------|--------|
| `gnomeBaseApps` = `[TextEditor, Loupe, Papers, Totem]` | ✅ Lines 8–14 |
| `gnomeDesktopOnlyApps` = `[Calculator, Calendar]` | ✅ Lines 16–19 |
| `gnomeAppsToInstall` = base `++ lib.optionals (role == "desktop") desktop` | ✅ Lines 22–24 |
| Hash = `builtins.substring 0 16 (builtins.hashString "sha256" ...)` | ✅ Lines 28–29 |
| Stamp path = `/var/lib/flatpak/.gnome-apps-installed-${gnomeAppsHash}` | ✅ Line 188 |
| Migration loop guarded by `lib.optionalString (role != "desktop")` | ✅ Lines 190–198 |
| `flatpak uninstall || true` (non-fatal) | ✅ Line 196 |
| `rm -f .gnome-apps-installed .gnome-apps-installed-*` before new stamp | ✅ Lines 203–204 |
| No other files modified | ✅ Confirmed via workspace inspection |

### 2. Nix Syntax — No Issues Found

- `let ... in { ... }` module structure is valid Nix. ✅
- `lib.optionals` returns `gnomeDesktopOnlyApps` when condition is true, `[]`
  when false — correct usage for list concatenation. ✅
- `lib.optionalString` inside the `script` string correctly evaluates the
  migration block at Nix eval time and embeds it into the shell script only
  for non-desktop roles. ✅
- `lib.concatStringsSep " " gnomeDesktopOnlyApps` inside the migration loop
  expands to `org.gnome.Calculator org.gnome.Calendar` — valid shell `for`
  loop input. ✅
- `lib.concatStringsSep " \\\n        " gnomeAppsToInstall` for the install
  command produces properly line-continued shell arguments. ✅
- No circular dependency: `config.vexos.branding.role` is declared in
  `modules/branding.nix` and has no dependency on any `gnome.nix` output.
  NixOS module evaluation is lazy; this resolves cleanly. ✅

### 3. Logic Correctness

**Base apps on all roles:**

| App | All roles? |
|-----|-----------|
| `org.gnome.TextEditor` | ✅ |
| `org.gnome.Loupe` | ✅ |
| `org.gnome.Papers` | ✅ |
| `org.gnome.Totem` | ✅ |

**Desktop-only apps:**

| App | Desktop only? |
|-----|--------------|
| `org.gnome.Calculator` | ✅ |
| `org.gnome.Calendar` | ✅ |

**Migration uninstall logic:**
- Guarded by `lib.optionalString (config.vexos.branding.role != "desktop")` — the
  block is absent from the script entirely on desktop. ✅
- Checks with `flatpak list --app --columns=application 2>/dev/null | grep -qx "$app"`
  before uninstalling — avoids spurious errors on fresh systems. ✅
- `flatpak uninstall ... || true` — non-fatal, service continues. ✅

**Stamp lifecycle:**
1. Early exit if new hash stamp exists. ✅
2. Migration uninstall (non-desktop only). ✅
3. `flatpak install` for role-appropriate app list. ✅
4. `rm -f` cleans both the old static stamp and all prior hash stamps. ✅
5. `touch "$STAMP"` writes new hash stamp. ✅

Order is correct: cleanup runs after successful install, before writing the
stamp. If `flatpak install` fails, no stamp is written and the service
retries on next boot. ✅

**Role configuration verified:**

| Configuration file | `vexos.branding.role` value |
|--------------------|-----------------------------|
| `configuration-desktop.nix` | `"desktop"` |
| `configuration-htpc.nix` | `"htpc"` (line 100) |
| `configuration-server.nix` | `"server"` (line 23) |
| `configuration-stateless.nix` | `"stateless"` (confirmed) |

### 4. Consistency — 100%

The implementation mirrors `modules/flatpak.nix` patterns with high fidelity:

| Pattern | `flatpak.nix` | `gnome.nix` (this change) |
|---------|--------------|--------------------------|
| Hash computation | `builtins.hashString "sha256" (lib.concatStringsSep "," appsToInstall)` | identical pattern |
| Hash truncation | `builtins.substring 0 16` | identical |
| Stamp path | `/var/lib/flatpak/.xxx-installed-${hash}` | identical prefix scheme |
| Install command | `flatpak install --noninteractive --assumeyes flathub \` | identical flags |

Comments in the module body are accurate and up to date. The `NOTE` comment at
line 55 (`gnome-text-editor`, `gnome-calculator`, and `gnome-calendar` via
Flatpak) correctly reflects the new desktop-only scope for Calculator and
Calendar.

### 5. Safety Checks

| Check | Result |
|-------|--------|
| `hardware-configuration.nix` not in repo | ✅ `file_search` returned no results |
| `system.stateVersion` unchanged | ✅ `"25.11"` in all configuration files; no changes detected |
| No new flake inputs added | ✅ Change is entirely within `modules/gnome.nix`; `flake.nix` untouched |
| No `nixpkgs.follows` concerns | ✅ No new inputs |

### 6. Minor Observations (Non-Blocking)

1. **`rm -f .gnome-apps-installed-*` glob scope**: On non-desktop roles this
   glob runs and removes all prior hash stamps including any that might be
   present from previous rebuilds. This is intentional and matches the
   `flatpak.nix` precedent — no accumulation of stale stamps. Confirmed safe.

2. **Desktop re-run on first rebuild**: Existing desktop systems will re-run
   the service once (old static stamp does not match new hash stamp). The
   install is idempotent — flatpak skips already-installed apps. No user
   impact. This is documented in the spec (Section 6, "Desktop role"). ✅

3. **No issues found** that require refinement.

---

## Verdict

**PASS**

The implementation is spec-compliant, syntactically correct, logically sound,
and consistent with established codebase patterns. All safety checks pass.
Build validation could not be executed on this Windows host — this is an
infrastructure constraint, not a code defect. The GitHub Actions CI workflow
(`.github/workflows/ci.yml`) will perform `nix flake check` and
`nixos-rebuild dry-build` on push, providing the authoritative build gate.

Code is ready for commit and push to GitHub once CI passes.
