# features.nix Untracked File — Review

## Spec Compliance

Implementation matches spec exactly: two one-line additions of `features.nix` to
existing force-add loops, no new mechanism introduced.

- `modules/nix.nix:166` — `features.nix` added to `vexos-update`'s per-run force-add
  loop, immediately followed by the existing "commit any newly staged files" step
  (`modules/nix.nix:174-179`), so it is committed before the `git+file://` dry-build and
  switch later in the same script.
- `scripts/install.sh:395` — `features.nix` added to the installer's equivalent
  force-add loop, ahead of its own `git+file://` dry-build/switch.

## Best Practices / Consistency

- Matches the exact existing pattern character-for-character (space-separated file list
  inside an existing guarded loop) — no new abstraction, no new `lib.mkIf`, no new
  option.
- Both files already guard with `if [ -f ... ]; then`, so hosts without a
  `features.nix` are unaffected (skipped silently, identical to how
  `server-services.nix` already behaves for hosts that never ran `just enable`).
- No changes to Nix option declarations, module imports, or the Module Architecture
  Pattern (Option B). This is a shell-script content change inside two existing
  `writeShellScriptBin`/installer scripts, not a module structure change.

## Completeness

Both known locations that perform this exact class of force-add (per repo-wide grep for
`git add -f` / `for _f in` / `for f in`) were updated. No other force-add loops exist in
the repo.

## Security

- No secrets touched. `features.nix` contains only boolean feature toggles
  (`vexos.features.<name>.enable`), never credentials — unlike `secrets/`, which
  remains untracked/`.gitignore`d and is unaffected by this change.
- No world-writable files introduced; no plaintext credentials added.

## Performance

Negligible — one extra `git add -f` check (file-existence test + no-op if absent) per
`vexos-update` run and per installer run.

## Build Validation

`sudo nixos-rebuild dry-build` requires root; this sandbox has `sudo` disabled
(`no new privileges` flag set), confirmed unavailable for this entire investigation.
Used the CI-equivalent safe substitute already documented in CLAUDE.md's Test Commands
(`nix eval --impure ".#nixosConfigurations.<target>.config.system.build.toplevel.drvPath"`)
which forces full evaluation without building.

| Target | Result |
|---|---|
| `nix flake show --impure` | PASS — all 30 `nixosConfigurations` + all `nixosModules.*Base` evaluate |
| `vexos-desktop-amd` | PASS — valid `.drv` produced |
| `vexos-desktop-nvidia` | PASS — valid `.drv` produced |
| `vexos-desktop-vm` | PASS — valid `.drv` produced |
| `vexos-server-amd` | PASS — valid `.drv` produced |
| `vexos-headless-server-amd` | PASS — valid `.drv` produced |
| `vexos-stateless-amd` | PASS — valid `.drv` produced (pre-existing, unrelated locked-password evaluation warning) |
| `vexos-htpc-amd` | PASS — valid `.drv` produced |

Additional checks:
- `git ls-files hardware-configuration.nix` → empty (not committed). PASS.
- `git diff --stat -- 'configuration-*.nix'` → empty (no `stateVersion` or role-config
  changes). PASS.
- No new flake inputs added — `follows` check not applicable.

This change cannot be fully verified end-to-end from this sandbox (no root, so the
actual `vexos-update` script cannot be executed against a real `/etc/nixos` git repo
here). The user should run `just update` once on an affected host and confirm
`features.nix` shows as tracked (`git -C /etc/nixos ls-files features.nix`) after the
run, and that feature-gated packages survive the update.

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 95% | A (cannot execute the live update script in this sandbox; static/eval verification only) |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 100% | A |

**Overall Grade: A (99%)**

## Result: PASS
