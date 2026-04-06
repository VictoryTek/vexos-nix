# Review: snapper + btrfs-assistant (modules/system.nix)

**Reviewer**: Phase 3 QA Subagent  
**Date**: 2026-04-05  
**Spec**: `.github/docs/subagent_docs/snapper_btrfs_spec.md`  
**Implementation files reviewed**:
- `modules/system.nix` (new)
- `hosts/amd.nix` (modified)
- `hosts/nvidia.nix` (modified)
- `hosts/intel.nix` (modified)
- `hosts/vm.nix` (unchanged — correct)
- `configuration.nix` (unchanged — correct)

---

## Build Validation Results

### `nix flake check` (pure mode)
**Result: FAIL**

```
error: path '.../modules/system.nix' does not exist
```

`modules/system.nix` was not staged in git. Nix flakes operate on the git tree; untracked files are invisible to the evaluator. The file existed on disk but was never added via `git add`.

### `nix flake check --impure` (after staging `modules/system.nix`)
**Result: PASS (EXIT:0)**

All four NixOS configurations evaluated successfully:
- `nixosConfigurations.vexos-amd` — ✓
- `nixosConfigurations.vexos-nvidia` — ✓
- `nixosConfigurations.vexos-intel` — ✓
- `nixosConfigurations.vexos-vm` — ✓

Plus all nixosModules outputs passed. Only pre-existing `builtins.derivation` warnings (unrelated to this change).

### `sudo nixos-rebuild dry-build`
**Result: NOT RUN** — Sudo requires a password on this machine. Not counted as a failure per review instructions.

---

## Findings by Checklist Category

### 1. Specification Compliance

Comparing spec (`snapper_btrfs_spec.md` Steps 2–3) with implementation (`modules/system.nix`):

| Spec requirement | Implemented? | Notes |
|---|---|---|
| `services.snapper.configs.root.SUBVOLUME = "/"` | ✅ | Present |
| `services.snapper.configs.root.FSTYPE = "btrfs"` | ❌ | Absent — uses NixOS default "btrfs" (functionally OK but spec is explicit) |
| `services.snapper.configs.root.ALLOW_USERS = [ "nimda" ]` | ✅ | Present |
| `services.snapper.configs.root.TIMELINE_CREATE = true` | ✅ | Present |
| `services.snapper.configs.root.TIMELINE_CLEANUP = true` | ✅ | Present |
| `services.snapper.configs.root.TIMELINE_LIMIT_HOURLY = 5` | ✅ | Present |
| `services.snapper.configs.root.TIMELINE_LIMIT_DAILY = 7` | ✅ | Present |
| `services.snapper.configs.root.TIMELINE_LIMIT_WEEKLY = 4` | ❌ **CRITICAL** | Set to `0` — disables weekly snapshots |
| `services.snapper.configs.root.TIMELINE_LIMIT_MONTHLY = 3` | ❌ **CRITICAL** | Set to `0` — disables monthly snapshots |
| `services.snapper.configs.root.TIMELINE_LIMIT_YEARLY = 0` | ✅ | Present |
| `services.snapper.snapshotRootOnBoot = true` | ✅ | Present |
| `services.snapper.snapshotInterval = "hourly"` | ❌ | Absent — uses NixOS default "hourly" (functionally equivalent) |
| `services.snapper.cleanupInterval = "1d"` | ❌ | Absent — uses NixOS default "1d" (functionally equivalent) |
| `services.snapper.persistentTimer = true` | ❌ **WARNING** | Absent — spec requires it to re-fire missed timers after suspend |
| `services.btrfs.autoScrub` block | ❌ **CRITICAL** | Entirely absent from module |
| `pkgs.btrfs-assistant` | ✅ | Present |
| `pkgs.btrfs-progs` | ❌ **CRITICAL** | Absent from systemPackages |
| Import in `hosts/amd.nix` | ✅ | `../modules/system.nix` added |
| Import in `hosts/nvidia.nix` | ✅ | `../modules/system.nix` added |
| Import in `hosts/intel.nix` | ✅ | `../modules/system.nix` added |
| NOT imported in `hosts/vm.nix` | ✅ | Correct — vm.nix unmodified |

**Not in spec but added**:
- `NUMBER_LIMIT = "50"` — extra addition, valid snapper option (evaluates without error), not harmful
- `NUMBER_LIMIT_IMPORTANT = "10"` — extra addition, valid snapper option, not harmful

**Grade: 65%** — Core structure is correct; four spec-required items are missing.

---

### 2. Best Practices

- ✅ Dedicated module file, one concern per file — consistent with project pattern
- ✅ Header comment explains purpose and includes the `DO NOT import in vm.nix` notice
- ✅ Config named `root` — required for `snapper-boot.service` to trigger correctly
- ✅ `ALLOW_USERS` uses the project's actual primary user `nimda`
- ❌ `services.btrfs.autoScrub` absent — monthly scrub is a critical btrfs maintenance best practice
- ❌ `btrfs-progs` absent — `btrfs-assistant` depends on it at runtime for operations like balance/scrub; the spec explicitly includes it

**Grade: 75%**

---

### 3. Functionality

- ✅ Snapper timeline will activate (TIMELINE_CREATE + TIMELINE_CLEANUP both true)
- ✅ Boot snapshots will work (`snapshotRootOnBoot = true` + config named `root`)
- ✅ User `nimda` can run snapper without sudo
- ❌ **Weekly and monthly snapshot retention is broken** — `TIMELINE_LIMIT_WEEKLY = 0` and `TIMELINE_LIMIT_MONTHLY = 0` effectively disable those retention tiers entirely, contrary to spec's 4+3 policy
- ❌ `persistentTimer = false` (default) means hourly snapshots are silently skipped after suspend, leaving gaps in the timeline
- ❌ No monthly btrfs scrub — filesystem integrity not monitored

**Grade: 65%**

---

### 4. Code Quality

- ✅ Valid Nix syntax — evaluates without errors
- ✅ Consistent indentation (2 spaces)
- ✅ Section comment header `# ---------- Snapper ----------` follows project style
- ✅ Clean, readable attribute assignments
- ⚠️ `NUMBER_LIMIT = "50"` — string type used (correct for NixOS snapper module's freeform values), but undocumented deviation from spec; if this is intentional it should be commented
- ⚠️ Top-level `services.snapper.configs = { ... };` is split from `services.snapper.snapshotRootOnBoot = true;` on a separate line rather than combined in a single `services.snapper = { ... }` block as shown in the spec — minor style inconsistency but functionally identical

**Grade: 82%**

---

### 5. Security

- ✅ `ALLOW_USERS = [ "nimda" ]` — only the primary non-root user has snapper access
- ✅ No world-accessible snapshot permissions configured
- ✅ No hardcoded credentials or secrets
- ✅ No world-writable paths introduced
- ✅ No additional ports or network exposure
- ✅ Module does not override any security-related NixOS options

**Grade: 100%**

---

### 6. Performance

- ✅ Snapshot limits are conservative: 5 hourly, 7 daily (steady-state ~12 snapshots from timeline)
- ✅ `NUMBER_LIMIT = "50"` provides a hard cap on total snapshot count
- ❌ Monthly scrub absent — without it, silent btrfs filesystem errors may accumulate (performance and data integrity concern over time)
- ⚠️ Weekly and monthly retention disabled (set to 0) — while reducing snapshot count is good for performance, it contradicts the intentional policy stated in the spec

**Grade: 80%**

---

### 7. Consistency

- ✅ Module file header format matches other modules (`# modules/system.nix` + description comment)
- ✅ `{ pkgs, ... }: { ... }` module signature consistent with `modules/audio.nix`, `modules/gaming.nix`, etc.
- ✅ `environment.systemPackages = with pkgs; [ ... ]` pattern consistent with project
- ✅ Import path style (`../modules/system.nix`) consistent with existing imports in host files
- ✅ `hosts/vm.nix` correctly left unmodified

**Grade: 97%**

---

### 8. Build Success

- ❌ **`nix flake check` (pure mode) FAILS** — `modules/system.nix` not staged in git at implementation time
- ✅ **`nix flake check --impure` PASSES** — after staging the file (EXIT:0, all 4 configs pass)
- ⚠️ `sudo nixos-rebuild dry-build` — not run (password required, not counted as failure)

The pure-mode failure is a CRITICAL process gap: implementations must stage all new files before the work is considered complete. The underlying Nix code evaluates correctly once the file is accessible.

**Grade: 50%** — Build passes only with an impure flag and after manually staging the file; pure-mode `nix flake check` fails as delivered.

---

## Summary of Issues

### CRITICAL

| # | Issue | File | Detail |
|---|---|---|---|
| C1 | `modules/system.nix` not staged in git | repository | File was created but never `git add`-ed. Pure `nix flake check` fails. |
| C2 | `services.btrfs.autoScrub` entirely absent | `modules/system.nix` | Spec explicitly requires monthly scrub block. |
| C3 | `btrfs-progs` missing from `systemPackages` | `modules/system.nix` | Spec requires `pkgs.btrfs-progs`. |
| C4 | `TIMELINE_LIMIT_WEEKLY = 0` | `modules/system.nix` | Spec requires `4`. Setting to 0 disables weekly retention tier. |
| C5 | `TIMELINE_LIMIT_MONTHLY = 0` | `modules/system.nix` | Spec requires `3`. Setting to 0 disables monthly retention tier. |

### WARNING

| # | Issue | File | Detail |
|---|---|---|---|
| W1 | `services.snapper.persistentTimer = true` absent | `modules/system.nix` | Spec requires this to re-fire missed timers after suspend/poweroff. |
| W2 | `FSTYPE = "btrfs"` absent | `modules/system.nix` | Spec sets it explicitly for clarity. Functionally, NixOS defaults to "btrfs". |
| W3 | `snapshotInterval` and `cleanupInterval` absent | `modules/system.nix` | Spec sets them explicitly. Functionally equivalent to NixOS defaults. |

### INFO

| # | Note |
|---|---|
| I1 | `NUMBER_LIMIT = "50"` and `NUMBER_LIMIT_IMPORTANT = "10"` added (not in spec). Both evaluate correctly in NixOS 25.11. Not harmful but undocumented deviation. |
| I2 | Module was renamed from `modules/snapper.nix` to `modules/system.nix` (intentional per task description). |
| I3 | `hosts/vm.nix` correctly unchanged — `modules/system.nix` is NOT imported there. ✓ |

---

## Score Table

| Category | Score | Grade |
|---|---|---|
| Specification Compliance | 65% | D |
| Best Practices | 75% | C |
| Functionality | 65% | D |
| Code Quality | 82% | B |
| Security | 100% | A |
| Performance | 80% | B |
| Consistency | 97% | A |
| Build Success | 50% | F |

**Overall Grade: D (77% weighted — heavily penalized by critical missing features and build failure)**

---

## Verdict

**NEEDS_REFINEMENT**

The implementation has a correct structural foundation but is missing five spec-required items and failed the primary build validation step. All five critical issues must be resolved before this can be approved:

1. Stage all modified and new files (`git add modules/system.nix hosts/amd.nix hosts/nvidia.nix hosts/intel.nix`)
2. Add `services.btrfs.autoScrub` block to `modules/system.nix`
3. Add `pkgs.btrfs-progs` to `environment.systemPackages` in `modules/system.nix`
4. Set `TIMELINE_LIMIT_WEEKLY = 4` in `modules/system.nix`
5. Set `TIMELINE_LIMIT_MONTHLY = 3` in `modules/system.nix`

And the following warning should also be addressed:

6. Add `services.snapper.persistentTimer = true` to `modules/system.nix`
