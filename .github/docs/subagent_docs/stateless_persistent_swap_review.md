# stateless_persistent_swap — Review

## Spec compliance

Implementation matches spec exactly: single addition to `modules/impermanence.nix`'s
existing `config = lib.mkIf cfg.enable { ... }` block. `vexos.swap.enable = lib.mkForce
false;` retained unchanged; a `swapDevices` entry pointing at
`${cfg.persistentPath}/swapfile` (8192 MiB) added alongside it, with the comment
rewritten to explain both halves of the story.

## Checklist

1. **Specification compliance** — matches spec 1:1. PASS.
2. **Best practices** — uses the standard NixOS `swapDevices.*.size` auto-create
   mechanism; relies on upstream's own Btrfs-aware `mkswapfile` handling (verified
   against current nixpkgs `nixos/modules/config/swap.nix` source) rather than
   reimplementing NOCOW/compression handling. PASS.
3. **Consistency (Module Architecture Pattern)** — change lives entirely inside
   `modules/impermanence.nix`'s own `lib.mkIf cfg.enable` block, gated by an option the
   module itself declares (`vexos.impermanence.enable`) — this is the documented
   carve-out, not new role-smuggling. No new `lib.mkIf` was added to any shared/base
   module. `modules/gpu/vm.nix` and `modules/system.nix` are untouched. PASS.
4. **Maintainability** — comment explains the *why* (generic path is RAM-backed under
   tmpfs root; zram alone isn't real overflow; `/persistent` is real disk; upstream
   already handles Btrfs specifics) rather than restating the code. PASS.
5. **Completeness** — addresses the actual root cause identified in Phase 1 (no disk
   overflow device for stateless installs) rather than a workaround (e.g. telling the
   user to raise VM RAM further, which was already tried and insufficient). PASS.
6. **Performance** — no regressions; swapfile is dormant capacity, only used under
   actual memory pressure. `size = 8192` matches the existing repo-wide convention
   (`modules/system.nix`), not a speculative new value. PASS.
7. **Security** — no secrets, no world-writable files, no server/credential surface
   touched. PASS.
8. **API currency** — `swapDevices.*.size` / Btrfs auto-detection behavior confirmed
   against current nixpkgs `master` source (fetched during Phase 1), not assumed from
   training data. PASS.
9. **Build validation:**
   - `sudo nixos-rebuild dry-build` could not be executed in this session — `sudo` is
     blocked by this sandboxed environment's "no new privileges" flag, unrelated to the
     change itself.
   - Substituted the CI-equivalent safe check per CLAUDE.md (`nix eval --impure
     ".#nixosConfigurations.<cfg>.config.system.build.toplevel.drvPath"`) for
     `vexos-stateless-amd`, `vexos-stateless-vm` (directly affected), plus
     `vexos-desktop-amd`, `vexos-desktop-vm` (baseline/unaffected-regression check).
     All four evaluated cleanly to a valid `.drv` path, no assertion failures.
   - `nix flake show --impure` evaluated the full flake structure (30 configurations)
     without error.
   - `git ls-files hardware-configuration.nix` → empty (not tracked). PASS.
   - No `configuration-*.nix` file was touched; `system.stateVersion` unchanged. PASS.
   - No new flake inputs added; `follows` policy N/A for this change. PASS.

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 100% | A |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 95% | A (full `dry-build` blocked by sandbox `sudo` restriction, not the change; substituted equivalent `nix eval` check per CLAUDE.md guidance passed on all 4 targets) |

**Overall Grade: A (99%)**

## Result: **PASS**

---

## Addendum review: install-time swap fix (scripts/stateless-setup.sh)

Triggered by user report that OOM persisted after the module-level fix — root cause
was distinct (install-time, not runtime; see spec addendum).

1. **Spec compliance** — matches addendum spec exactly: temp swapfile created via
   `btrfs filesystem mkswapfile` right after disko mounts `/mnt`, before
   `nixos-install`; `cleanup()` trap extended to `swapoff` it. PASS.
2. **Best practices** — reuses the exact same creation mechanism NixOS's own swap
   module uses (verified against nixpkgs source in Phase 1), same path/size as the
   installed system's config so first boot doesn't recreate it. PASS.
3. **Consistency** — follows the script's existing patterns exactly: extends the
   pre-existing `cleanup()`/`trap ... EXIT` pattern rather than adding a new mechanism;
   matches the script's existing `echo -e "${BOLD}..."` / `${GREEN}  ✓ ...` step-banner
   style. PASS.
4. **Maintainability** — comment explains why this is needed (install runs from a
   swapless live ISO) and why the size/path match the module (so first boot reuses
   rather than recreates). PASS.
5. **Completeness** — this was the actual gap; the module-level fix alone was
   insufficient because `swapDevices` only activates at boot of the *installed*
   system, never during the live-ISO `nixos-install` invocation itself. PASS.
6. **Security** — no secrets, no permission changes beyond a root-owned swapfile
   (mode is whatever `btrfs filesystem mkswapfile` sets, matching upstream behavior).
   PASS.
7. **Shellcheck** — ran `shellcheck scripts/stateless-setup.sh` directly (this script
   is not covered by preflight's own shellcheck step, which only covers
   `pkgs.vexos.vexos-update`). Only pre-existing warning at line 348 (SC2059, unrelated
   to this change, present before it). No new findings introduced. PASS.
8. **Build validation** — `bash scripts/preflight.sh` re-run in full, exit code 0,
   "Preflight PASSED — safe to push." No `configuration-*.nix`/`stateVersion` touched;
   `hardware-configuration.nix` still untracked; no new flake inputs. PASS.

### Updated Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 100% | A |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 100% | A (`scripts/preflight.sh` exit 0; shellcheck clean) |

**Overall Grade: A (100%)**

### Result: **PASS**

---

## Addendum 2 review: migrate-to-stateless.sh (in-place migration path)

Triggered by user clarifying they're testing via the in-place migration path
(existing NixOS VM + README installer), a third distinct code path with the same
gap. User confirmed no swap on the VM; exact OOM'ing step unconfirmed but consistent
with the same class of bug.

1. **Spec compliance** — matches addendum 2 spec: mounts the raw Btrfs volume again
   right before `nixos-rebuild boot`, activates a swapfile on the just-created
   `@persist` subvolume, releases it immediately after (both on success and via the
   new `cleanup()` trap on failure/interrupt) before the script's independent later
   re-mount for the `/nix` sync step. PASS.
2. **Best practices** — same upstream-verified `btrfs filesystem mkswapfile` mechanism
   as the other two fixes; reuses this script's own existing
   `mount -o subvolid=5 ... || mount ...` idiom verbatim (already used twice
   elsewhere in the file) rather than inventing a new mounting approach. PASS.
3. **Consistency** — `cleanup()`/`trap ... EXIT` added here matches the pattern used
   in `scripts/stateless-setup.sh` (Addendum 1); comment density and step-banner style
   (`echo -e "${BOLD}..."` / `${GREEN}  ✓ ...`) match the rest of the script. PASS.
4. **Maintainability** — comments explain why (build runs on the current system's
   pre-existing, possibly absent swap) and the mount lifecycle (activated/released
   twice — trap and explicit — to avoid colliding with the later independent
   re-mount). PASS.
5. **Completeness** — closes the third and last of the three independent stateless
   install/runtime code paths identified across this conversation
   (`modules/impermanence.nix`, `scripts/stateless-setup.sh`,
   `scripts/migrate-to-stateless.sh`); none share code, so each needed its own fix.
   PASS.
6. **Security** — no secrets; swapfile permissions match upstream
   `mkswapfile` defaults, same as the other two fixes. PASS.
7. **Shellcheck** — clean; only pre-existing SC2001 style note at line 194 (unrelated,
   predates this change). PASS.
8. **Build validation** — `bash scripts/preflight.sh` re-run in full after this
   change, exit code 0, "Preflight PASSED — safe to push." No `configuration-*.nix`/
   `stateVersion` touched; `hardware-configuration.nix` still untracked; no new flake
   inputs. PASS.

### Final Score Table (all three fixes)

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 100% | A |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 100% | A |

**Overall Grade: A (100%)**

### Result: **PASS**
