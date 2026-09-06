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
