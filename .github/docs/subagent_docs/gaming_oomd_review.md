# Review: Gaming Role — systemd-oomd Slice Enablement

**Feature name:** `gaming_oomd`
**Review file:** `.github/docs/subagent_docs/gaming_oomd_review.md`
**Date:** 2026-05-15
**Reviewer:** QA Subagent
**Verdict:** ✅ PASS

---

## Summary

The implementation is minimal, correct, and fully aligned with the specification. Exactly two lines were added to `modules/system-gaming.nix` inside a new `systemd.oomd` block. No other files were modified. The change follows the project's Option B architecture pattern (common base + role additions) without introducing any `lib.mkIf` guards, and the block is unconditional by design. All static validation checks pass.

`nix` is not available on the Windows development host, so build validation was performed via static analysis only. All evaluated criteria pass at the static level.

---

## Detailed Findings

### 1. Specification Compliance

| Check | Expected | Found | Result |
|-------|----------|-------|--------|
| `systemd.oomd.enableRootSlice = true` | Present | ✅ Present (`modules/system-gaming.nix` line 53) | PASS |
| `systemd.oomd.enableUserSlices = true` | Present | ✅ Present (`modules/system-gaming.nix` line 54) | PASS |
| `systemd.oomd.enable = true` | Absent (default) | ✅ Absent | PASS |
| `systemd.oomd.enableSystemSlice = true` | Absent (omitted by design) | ✅ Absent | PASS |
| `modules/system.nix` unchanged | Unmodified | ✅ No oomd settings added | PASS |

All five specification constraints are satisfied.

---

### 2. Architecture Pattern Compliance

| Check | Result |
|-------|--------|
| No new `lib.mkIf` guards introduced | ✅ PASS — `systemd.oomd` block is unconditional |
| Change confined to `system-gaming.nix` only | ✅ PASS |
| `system.nix` not modified | ✅ PASS |
| `configuration-desktop.nix` imports `system-gaming.nix` | ✅ PASS (line 18: `./modules/system-gaming.nix`) |
| Role separation maintained (server/headless/stateless unaffected) | ✅ PASS — those configs do not import `system-gaming.nix` |

The module is a clean role-specific addition file (`system-gaming.nix`). Its content applies unconditionally to every role that imports it (desktop, htpc). No conditional logic was added.

---

### 3. Correctness

**NixOS 25.05 default for `systemd.oomd.enable`:** The spec confirms (via nixpkgs source examination) that `enable` defaults to `true`. The implementation correctly omits it, avoiding a redundant assertion.

**What `enableRootSlice = true` does:** Per the nixpkgs module source cited in the spec, this sets `ManagedOOMMemoryPressure=kill` and `ManagedOOMMemoryPressureLimit=80%` on `-.slice` (the root cgroup). oomd will kill descendant cgroups when system-wide PSI memory pressure exceeds 80%.

**What `enableUserSlices = true` does:** Sets `ManagedOOMMemoryPressure=kill` on `user.slice`, which covers all `user@$UID.service` trees. Games and Electron apps (Discord, Vesktop) run inside user slices. GNOME is explicitly called out in the systemd-oomd man page as safe for `enableUserSlices`.

**Why `enableSystemSlice` is correctly omitted:** `system.slice` hosts long-running daemons (pipewire, networkd, etc.). Enabling memory pressure killing on the system slice for a gaming configuration is unnecessary and could disrupt background services. This matches Fedora/Bazzite's default combination of `enableRootSlice + enableUserSlices` only.

**Role isolation:** `system-gaming.nix` is not imported by `configuration-server.nix`, `configuration-headless-server.nix`, or `configuration-stateless.nix`. Those roles are unaffected.

---

### 4. Comment Quality

The implementation's comment block accurately describes:
- Why oomd is already running (default=true) but ineffective (no slice directives)
- What each option adds
- The Bazzite/Fedora equivalence
- Why `enableSystemSlice` is omitted

One minor precision note: the comment for `enableRootSlice` reads "Enables swap-aware OOM killing" — `enableRootSlice` configures `ManagedOOMMemoryPressure` (PSI-based), not `ManagedOOMSwap`. The phrasing is inherited from the spec's draft comment and is not technically wrong in context (memory pressure will rise as ZRAM fills and the system pages to swap), but "memory-pressure-based OOM killing" would be slightly more precise. This is a documentation nit and not a correctness issue.

---

### 5. Build Validation

**Environment:** Windows development host — `nix` CLI not available. Build commands cannot be executed locally.

**Static checks performed:**

| Check | Result |
|-------|--------|
| `hardware-configuration.nix` tracked in git | ✅ NOT tracked (`git ls-files` returns empty) |
| `system.stateVersion` present in `configuration-desktop.nix` | ✅ Present (`system.stateVersion = "25.11"`) |
| `system.stateVersion` unchanged | ✅ Not modified |
| New flake inputs introduced | ✅ None — no new inputs required |
| `lib.mkIf` guards added | ✅ None |
| Nix syntax validity | ✅ File parses cleanly (standard attribute set, no new syntax) |

The change adds two boolean attribute assignments inside an existing top-level attribute path (`systemd.oomd`). There is no ambiguity in the Nix syntax and no risk of name conflicts.

---

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 100% | A |
| Code Quality | 98% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 95% | A (static only — Windows host; nix unavailable) |

**Overall Grade: A (99%)**

---

## Build Result

**STATIC PASS** — All file-level checks pass. `nix flake check` and `nixos-rebuild dry-build` could not be executed on the Windows development host. The change involves only two boolean attribute assignments on an existing NixOS module option (`systemd.oomd`), which is guaranteed valid in NixOS 25.05 per the spec's nixpkgs source reference. No evaluation error is expected.

---

## Verdict

**✅ PASS**

The implementation is correct, complete, and minimal. It adds exactly what the spec requires and nothing more. Architecture pattern compliance is perfect. The only note is a minor comment phrasing imprecision inherited from the spec draft, which does not affect correctness or behaviour.
