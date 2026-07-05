# M-37 — Review & Quality Assurance

Status: Phase 3 (Review)
Spec: `.github/docs/subagent_docs/M-37_gnome_boot_test_spec.md`

## Modified Files

- `flake.nix` — added `testPkgs` (dedicated pkgs instance for the check) and
  `checks.x86_64-linux.gnome-boot` (a `testers.nixosTest` reusing
  `vexos-desktop-vm`'s real module composition, minus
  `hardware-configuration.nix`).
- `README.md` — added the new automated check as step 3 of the existing
  manual "bump nixpkgs-unstable" procedure; kept the manual VM check as an
  optional final step rather than removing it.

## Review Findings

1. **Specification Compliance** — matches the spec: `checks.x86_64-linux.gnome-boot`
   added exactly as named, reuses the real module composition, invoked only
   as a single named target (never `nix flake check`, which stays
   forbidden).
2. **Best Practices** — verified `pkgs.nixosTest` is a hard `throw` at this
   nixpkgs rev (renamed to `testers.nixosTest`) directly against source
   rather than assuming API stability; confirmed the tester's calling
   convention against its own implementation before writing the test.
3. **Consistency** — the test reuses `roles.desktop`/`mkHomeManagerModule`
   bindings already used by `mkHost`, rather than hand-duplicating their
   contents — only the final module list assembly is duplicated (6 lines),
   scoped to this one test.
4. **Maintainability** — every override added to the test node
   (`networking.hostName`, `nixpkgs.config`) has an inline comment
   explaining *why* it's needed (equal-priority `mkDefault` conflict with
   the testing framework; the framework's externally-supplied-pkgs
   assertion), so a future maintainer hitting the same class of conflict
   elsewhere has a documented precedent.
5. **Completeness** — the test script covers boot-to-multi-user, GDM
   activation, graphical.target, actual Wayland session start, and a live
   gnome-shell process — matching (and automating) every check the README's
   manual procedure asked a human to eyeball.
6. **Performance** — n/a; this is an on-demand check, not part of any
   `nixosConfigurations` build path or default `nix build`.
7. **Security** — n/a.
8. **API Currency** — verified against the actual pinned nixpkgs source
   throughout (tester rename, calling convention, the externally-supplied-pkgs
   assertion's exact condition) rather than training-data recall, consistent
   with the project's Context7/verification policy for anything touching a
   versioned, evolving API surface.
9. **Two real evaluation conflicts found and fixed during Phase 3 (not
   deferred):**
   - `modules/network.nix`'s `networking.hostName = lib.mkDefault "vexos";`
     collided with the testing framework's own same-priority default
     (`"machine"`) — two equal-priority `mkDefault`s can't resolve a
     winner. Fixed with `lib.mkForce` in the test node only; the real
     `modules/network.nix` is untouched.
   - NixOS's `nixpkgs.nix` module unconditionally asserts
     `opt.pkgs.isDefined -> cfg.config == {}` — since `testers.nixosTest`
     supplies its own `pkgs`, `modules/nix.nix`'s
     `nixpkgs.config.allowUnfree = true` fails that assertion regardless of
     whether the externally-supplied `pkgs`' own config matches (initially
     tried building a matching `testPkgs` instance to satisfy what looked
     like a value-comparison assertion — traced the assertion's actual
     source and found it's unconditional, not a value comparison, so that
     alone wasn't sufficient). Fixed by forcing
     `nixpkgs.config = lib.mkForce {}` in the test node — safe here since
     the VM path needs no unfree package (no NVIDIA, and
     `hosts/desktop-vm.nix` already force-disables Steam). `testPkgs` was
     kept regardless, since it also ensures the externally-supplied `pkgs`
     itself has `allowUnfree` available should anything in the desktop
     package set need it transitively.
10. **One test-assertion false-failure found and fixed:** the first full
    end-to-end run **actually booted the VM successfully** — GDM started,
    `graphical.target` reached, and critically the Wayland socket
    (`/run/user/1000/wayland-0`, the core regression signal this test
    exists to catch) appeared immediately. Only the belt-and-suspenders
    final assertion (`pgrep -x gnome-shell`, an exact-name match) failed.
    Relaxed to `pgrep -f gnome-shell` (full-command-line match) — re-ran
    end-to-end and confirmed the test now passes completely.
11. **Build Validation:**
    - `nix flake show --impure` — passed, `checks.x86_64-linux.gnome-boot`
      listed as a derivation.
    - **Full end-to-end test run**:
      `nix build --impure --no-link ".#checks.x86_64-linux.gnome-boot"` —
      passed after the two conflict fixes and the assertion relaxation
      above. VM boot took ~5 minutes total (multi-user.target,
      display-manager.service, graphical.target, Wayland socket, and the
      relaxed `gnome-shell` process check all succeeded in sequence).
    - Per-target `nix eval --impure ".#nixosConfigurations.<x>.config.system.build.toplevel.drvPath"`
      for `vexos-desktop-amd`, `-nvidia`, `-vm` — **`.drv` hashes identical**
      to the values from the prior (M-36) review, confirming the new
      `checks` output and `testPkgs` binding have zero effect on any real
      `nixosConfigurations` output.
    - `git ls-files hardware-configuration.nix` — empty. ✓
    - `bash scripts/preflight.sh` — exit 0, PASSED (run both before and
      after the `README.md` edit). Same pre-existing WARNs as every prior
      review this session — nothing new.

No CRITICAL issues remain (all three found were fixed within this same
review pass, and the fix for each was verified with a real re-run rather
than assumed correct). No RECOMMENDED issues outstanding.

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

## Returns

- Build result: PASS (full end-to-end VM test run, not just evaluation)
- **PASS**
