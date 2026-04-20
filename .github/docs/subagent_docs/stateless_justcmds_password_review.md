# Review: Stateless `just` Commands & Default Password

**Feature:** `stateless_justcmds_password`
**Date:** 2026-04-19
**Reviewer:** Review Subagent (Phase 3)
**Spec:** `.github/docs/subagent_docs/stateless_justcmds_password_spec.md`

---

## Build Validation Results

| Command | Result | Notes |
|---------|--------|-------|
| `nix flake check` | ❌ FAIL (pre-existing) | `error: access to absolute path '/etc' is forbidden in pure evaluation mode` — identical failure confirmed on the **original HEAD** via `git stash` + re-run. NOT a regression from these changes. |
| `sudo nixos-rebuild dry-build --flake .#vexos-stateless-amd` | ⚠ SKIPPED | `sudo` is restricted in this evaluation environment ("no new privileges" flag set in container). |
| `sudo nixos-rebuild dry-build --flake .#vexos-stateless-vm` | ⚠ SKIPPED | Same sudo restriction. |

**Build verdict:** `nix flake check` failure is **pre-existing** (confirmed by baseline check on unmodified HEAD). The thin-wrapper architecture intentionally omits `hardware-configuration.nix` from the repo; its import from `/etc/nixos/` violates pure eval mode. This is a known architectural property of the project, not a regression introduced by these changes.

---

## Detailed Review Findings

### 1. `modules/impermanence.nix` — PASS

| Check | Result |
|-------|--------|
| `/etc/nixos` added to `environment.persistence."/persistent".directories` | ✓ |
| Positioned after `/var/lib/nixos`, before omitted-section comment | ✓ |
| Comment explains rationale (vexos-variant recreated by env.etc, flake.nix is not) | ✓ |
| Nix syntax correct | ✓ |

The diff is minimal and precise — 7 lines added (1 entry + 5-line explanatory comment + blank line). Comment accurately describes the distinction between `environment.etc`-managed files and user-managed files. No issues.

---

### 2. `scripts/stateless-setup.sh` — PASS

| Check | Result |
|-------|--------|
| `mkdir -p /mnt/persistent/etc/nixos` called before copy | ✓ |
| Copies `flake.nix`, `hardware-configuration.nix`, AND `flake.lock` | ✓ |
| Copy step placed AFTER `nixos-install` completes | ✓ |
| Target path `/mnt/persistent/etc/nixos` is the @persist Btrfs subvolume (disko mounts it there) | ✓ |
| Post-install banner shows `nimda` / `vexos` credentials | ✓ |
| Password-reset behavioural warning included | ✓ |
| Old "Set a root password" step removed | ✓ |
| Explanatory comment added above the persist block | ✓ |

**Minor deviation from spec:** The spec specified a prominent banner with `━━━` separators around the password warning. The implementation uses a simpler `${BOLD}Default login credentials:${RESET}` header. The content is functionally equivalent and communicates clearly. Acceptable.

**Extra credit:** Copies `flake.lock` in addition to the two files spec-required. This is correct and desirable — without `flake.lock` the rebuild would use a different lock state.

---

### 3. `scripts/migrate-to-stateless.sh` — ❌ CRITICAL BUG

| Check | Result |
|-------|--------|
| Config files copied to persistent storage | ✓ (logically present) |
| Completion message shows credentials | ✓ |
| Password-reset warning included | ✓ |
| **Files copied to the correct Btrfs subvolume** | ❌ **CRITICAL** |

**Critical Bug — Wrong copy destination:**

The new persist block writes to `/persistent/etc/nixos/`:

```bash
mkdir -p /persistent/etc/nixos
cp /etc/nixos/flake.nix /persistent/etc/nixos/ ...
```

This block executes AFTER the raw Btrfs mount (`${BTRFS_MOUNT}`) has been unmounted (it is placed after `umount "${BTRFS_MOUNT}"` and `rmdir "${BTRFS_MOUNT}"`). At that point, `/persistent` does NOT exist as a Btrfs subvolume mount on the **running non-stateless system** — the migration script is running on a standard NixOS system where the root filesystem is a flat Btrfs partition. 

`mkdir -p /persistent/etc/nixos` creates a directory on the **OLD flat Btrfs root subvolume**, NOT inside the `@persist` Btrfs subvolume. After the first stateless reboot:

- `@nix` is mounted at `/nix`
- `@persist` is mounted at `/persistent` → this subvolume is **empty** (nothing was written to it)
- The `@persist` subvolume was never populated because the copy went to the wrong location

The impermanence module finds no files in `/persistent/etc/nixos/` on first stateless boot, creates an empty bind-mount, and `just rebuild` / `just update` still fail — **the Bug 1 fix for the migration path is fully defeated**.

**Root cause of the bug:** The implementation copied the approach from the setup script (`/mnt/persistent/...`) where disko does mount `@persist` at `/mnt/persistent`. In the migration context, the `@persist` subvolume is only accessible via the raw Btrfs mount at `${BTRFS_MOUNT}` (`/mnt/vexos-migrate-btrfs`). After that is unmounted, the subvolume is unreachable without remounting.

**Required fix:** Either:

**Option A** — Re-mount the raw Btrfs (separate step, cleanest):
```bash
echo -e "${BOLD}Persisting NixOS config files to @persist subvolume...${RESET}"
mkdir -p "${BTRFS_MOUNT}"
mount -o subvolid=5 "${ROOT_DEV_RAW}" "${BTRFS_MOUNT}" 2>/dev/null || \
  mount "${ROOT_DEV_RAW}" "${BTRFS_MOUNT}"
mkdir -p "${BTRFS_MOUNT}/@persist/etc/nixos"
cp /etc/nixos/flake.nix    "${BTRFS_MOUNT}/@persist/etc/nixos/" ...
cp /etc/nixos/flake.lock   "${BTRFS_MOUNT}/@persist/etc/nixos/" ...
cp /etc/nixos/hardware-configuration.nix "${BTRFS_MOUNT}/@persist/etc/nixos/" ...
umount "${BTRFS_MOUNT}"
rmdir "${BTRFS_MOUNT}" 2>/dev/null || true
```

**Option B** — Include within the existing @nix sync block BEFORE the umount (as the spec described):
Move the config copy step BEFORE the `umount "${BTRFS_MOUNT}"` line in the `/nix → @nix sync` block. Write to `"${BTRFS_MOUNT}/@persist/etc/nixos/"`.

Either option correctly targets the `@persist` subvolume. Option A is preferred because it keeps the persist step as a clearly separated, labelled section.

---

### 4. `justfile` — PASS

| Check | Result |
|-------|--------|
| `elif [[ "$variant" == *stateless* ]]` branch added after server `if` block | ✓ |
| `if/elif/fi` structure is syntactically correct bash | ✓ |
| Stateless section mentions password resets to `vexos` | ✓ |
| `Active role: stateless (ephemeral / tmpfs root)` label included | ✓ |

**Minor deviation from spec:** The spec included "Available recipes:" with a list of commands (`switch`, `rebuild`, etc.). The implementation omits this recipe list in favour of a shorter, focused reminder. This is a reasonable simplification — the recipe list is already shown by `just --list` which runs unconditionally above. No functional issue.

---

### 5. General Checks

| Check | Result |
|-------|--------|
| `system.stateVersion` unchanged in all files | ✓ |
| No new flake inputs added | ✓ |
| No new nixpkgs dependencies | ✓ |
| `hardware-configuration.nix` NOT committed to repo | ✓ |
| Code style consistent with surrounding code | ✓ |
| `set -euo pipefail` preserved in all scripts | ✓ |
| Color helper pattern followed | ✓ |

---

## Summary

| File | Status | Notes |
|------|--------|-------|
| `modules/impermanence.nix` | ✅ PASS | Correct, minimal, well-commented |
| `scripts/stateless-setup.sh` | ✅ PASS | Correct path, good content, minor style delta from spec |
| `scripts/migrate-to-stateless.sh` | ❌ NEEDS FIX | **Critical**: files copied to wrong filesystem (old root, not @persist subvolume) |
| `justfile` | ✅ PASS | Correct structure, appropriate content |

**Bug 1 fix status:**
- Fresh install path (`stateless-setup.sh`): ✅ Fixed correctly
- Migration path (`migrate-to-stateless.sh`): ❌ Not fixed — files land on the wrong subvolume

**Bug 2 fix status:**
- `stateless-setup.sh`: ✅ Credentials shown, warning included
- `migrate-to-stateless.sh`: ✅ Credentials shown, warning included (correct even with the Bug 1 regression)
- `justfile`: ✅ Runtime reminder shown

---

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 82% | B |
| Best Practices | 90% | A |
| Functionality | 62% | D |
| Code Quality | 88% | B+ |
| Security | 95% | A |
| Performance | 95% | A |
| Consistency | 90% | A |
| Build Success | 70% | C |

**Overall Grade: B- (84%)**

> Functionality is graded D because the primary purpose of the migrate-to-stateless.sh change (fixing `just` commands after stateless reboot for users who migrated) is completely negated by the wrong copy destination. Three of four files are correct and complete.

---

## Verdict: NEEDS_REFINEMENT

**Single required fix:** In `scripts/migrate-to-stateless.sh`, the config file copy step must target the `@persist` Btrfs subvolume at `${BTRFS_MOUNT}/@persist/etc/nixos/` (with a re-mount of the raw Btrfs), not `/persistent/etc/nixos/` which does not exist as the @persist subvolume on a pre-stateless system.

No other changes required. All other files are correct and complete.
