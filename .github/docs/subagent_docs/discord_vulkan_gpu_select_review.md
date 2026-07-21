# Discord/Vesktop Vulkan GPU selection fix — Review

Spec: `discord_vulkan_gpu_select_spec.md`
Modified files: `modules/gaming.nix`

## Findings

1. **Spec compliance:** implementation matches spec exactly — `nvidiaVkSelect`
   helper added to the module `let` block, applied to both `pkgs.unstable.vesktop`
   and `pkgs.discord` in `environment.systemPackages`. No option added, matching
   the spec's "single-host workaround, no new option" decision.
2. **Best practices:** `overrideAttrs` + `wrapProgram` in `postFixup` with
   `makeWrapper` added to `nativeBuildInputs` is the standard nixpkgs pattern
   for adding launch env vars without altering `.desktop` entries or binary
   names.
3. **Consistency (Module Architecture Pattern):** no new `lib.mkIf` guard
   added to a shared module. The wrapper is applied inside the existing
   `lib.mkIf cfg.enable` block, which is the module's own carve-out option
   (`vexos.features.gaming.enable`) — permitted per CLAUDE.md's exception.
4. **Maintainability:** comment explains the *why* (Mutter/NVIDIA regression,
   hardware topology) — non-obvious context a reader couldn't infer from the
   code. No comment restating *what* the code does.
5. **Completeness:** both affected packages wrapped; `.desktop` file
   references (`gnome-desktop.nix:89-90`, `home-desktop.nix:222`) unaffected
   since `overrideAttrs` preserves `$out` layout, binary names, and desktop
   entries.
6. **Performance:** `postFixup` wrapping is a fast fixup-phase step on
   already-built Electron binaries, not a recompilation.
7. **Security:** no secrets, no world-writable files, no plaintext
   credentials introduced.
8. **Surgical scope:** diff touches only the `let` block and the two package
   list lines that needed to change — no adjacent reformatting or unrelated
   edits.

## Build validation

- `nix flake show --impure`: PASS — full output tree evaluates, all
  `nixosConfigurations` and `nixosModules` listed.
- Environment note: `sudo` is blocked in this sandbox (`no new privileges`
  flag), and `nixos-rebuild dry-build` without sudo hits Nix pure-evaluation
  restrictions unrelated to this change. Used the CLAUDE.md-documented safe
  substitute instead: `nix eval --impure
  ".#nixosConfigurations.<target>.config.system.build.toplevel.drvPath"`,
  which forces the same full system evaluation CI relies on.
- `vexos-desktop-nvidia` (directly affected host): PASS — evaluates to a
  `.drv` path.
- `vexos-desktop-amd`: PASS
- `vexos-desktop-vm`: PASS
- `vexos-htpc-amd` (gaming.nix is imported by configuration-htpc.nix): PASS
- `vexos-server-amd` (gaming.nix is imported by configuration-server.nix):
  **FAIL — pre-existing, unrelated to this change.** Fails on the
  `modules/zfs-server.nix:85` assertion because `hosts/server-amd.nix:15`
  still carries the shared template placeholder `hostId = "a0000001"`. This
  assertion and placeholder predate this change (confirmed via `git diff`
  showing zero touched lines in `hosts/server-amd.nix` or
  `modules/zfs-server.nix`) and would fail identically on `main` without
  this patch applied. Not treated as CRITICAL for this review — it is a
  separate, pre-existing repo gap.
- `git ls-files hardware-configuration.nix`: empty — not committed. PASS
- `system.stateVersion`: `git diff -- configuration-*.nix` shows no
  stateVersion lines touched. PASS
- New flake inputs: none added. PASS (no `follows` check needed)

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 100% | A (pending user runtime confirmation of the actual fix) |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 90% | A- (4/5 required targets pass; 5th fails on unrelated pre-existing issue) |

**Overall Grade: A (98%)**

## Result

**PASS.** The one build failure (`vexos-server-amd`) is a pre-existing,
unrelated repo issue (uncustomized `hostId` template placeholder), not a
regression introduced by this change. No CRITICAL issues found. Proceeding
to Phase 6 (Preflight).
