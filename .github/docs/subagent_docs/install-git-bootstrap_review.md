# Review: install.sh — bootstrap git when missing on the host

Spec: `.github/docs/subagent_docs/install-git-bootstrap_spec.md`
Modified files: `scripts/install.sh` (+17 / −4, single file)

## Findings

1. **Specification Compliance** — Implementation matches the spec exactly: one
   resolution block added immediately before the git-track section; all four
   `sudo git` invocations replaced with `sudo "$GIT"`
   (`grep -n 'sudo git' scripts/install.sh` returns nothing). PASS.
2. **Best Practices** — `command -v` for detection, quoted `"$GIT"` expansion,
   absolute store path under sudo, no profile mutation (`--no-link`). Reuses the
   same `--extra-experimental-features` invocation style as the existing
   `nix flake update` call at line 390. PASS.
3. **Consistency** — Pure bash change; no Nix modules touched, so the Option B
   module architecture is unaffected. Comment style and section-header format
   match the surrounding script. PASS.
4. **Maintainability** — Self-documenting block with a comment explaining why
   (stock NixOS lacks git; sudo secure_path). PASS.
5. **Completeness** — Covers the only affected script. `stateless-setup.sh`
   also calls `sudo git` but only runs from the live ISO (which ships git);
   `migrate-to-stateless.sh` does not invoke git. Documented in spec. PASS.
6. **Performance** — Zero cost when git exists (`GIT="git"`, identical to
   before). On git-less hosts, one cached fetch (~50 MiB closure) replaces a
   hard crash. PASS.
7. **Security** — git fetched from cache.nixos.org via the standard flake
   registry with signature verification by the Nix daemon; no curl-pipe of new
   code, no secrets, no permission changes. The fix preserves the
   security-critical behavior (git-tracking keeps `secrets/` out of the store).
   PASS.
8. **API Currency** — `nix build --no-link --print-out-paths` is current CLI;
   no external libraries involved (Context7 n/a). PASS.

## Build Validation

- `bash -n scripts/install.sh` — OK
- `shellcheck -S warning scripts/install.sh` (shellcheck 0.11.0 via nixpkgs) — clean
- Runtime verification of the bootstrap command:
  `nix build nixpkgs#git --no-link --print-out-paths` →
  `/nix/store/...-git-2.51.2/bin/git`, executes (`git version 2.51.2`)
- `nix flake show --impure` — exit 0, all outputs enumerate
- `git ls-files hardware-configuration.nix` — empty (not tracked)
- `system.stateVersion` — no `configuration-*.nix` modified (diff touches only
  `scripts/install.sh`)
- No new flake inputs — `flake.nix` untouched
- Per-variant dry-build deferred to Phase 6 preflight (change touches no Nix
  evaluation path)

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
| Build Success | 100% | A |

**Overall Grade: A (100%)**

## Verdict

PASS
