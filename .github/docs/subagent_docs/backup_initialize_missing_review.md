# Review: restic `initialize = true` fix

## Spec compliance

Matches `.github/docs/subagent_docs/backup_initialize_missing_spec.md` exactly:
single-line `initialize = true;` added inside `services.restic.backups.main` in
`modules/server/backup.nix:174-188`, with a comment explaining why (upstream
default is `false`; without it the repo is never created and every backup run
fails with "repository does not exist"). No other structure touched.

## Best practices / consistency

Value-only addition to an existing `lib.mkIf cfg.enable { ... }` block — not a new
module, not a role/display/gaming `lib.mkIf` guard, so no Module Architecture
Pattern (Option B) concerns. Matches upstream's own documented example usage of
`initialize = true` for exactly this scenario.

## Maintainability / completeness

Fixes the root cause identified via direct evidence: the actual rendered
`preStart` script on the test VM contained no `restic init` line at all, and a
local `restic init` test against a nonexistent nested path confirmed restic
itself works fine once `initialize` is honored — the missing option was the
entire problem, not permissions, impermanence, or timing.

## Security

No secrets, credentials, or plaintext assignments touched.

## Build validation

- `git diff --name-only` → only `modules/server/backup.nix` changed.
- `nix flake show --impure` → previously validated structure unaffected (no new
  outputs/options added).
- `nix eval --impure ".#nixosConfigurations.<cfg>.config.system.build.toplevel.drvPath"`
  (safe CI-equivalent to dry-build; `sudo nixos-rebuild dry-build` unavailable —
  sudo blocked in this sandbox: `sudo: the "no new privileges" flag is set`):
  - `vexos-desktop-amd` → evaluates successfully, derivation produced.
  - `vexos-desktop-nvidia` → evaluates successfully, derivation produced.
  - `vexos-desktop-vm` → evaluates successfully, derivation produced.
  - `vexos-server-amd` / `vexos-headless-server-amd` (required — this change
    touches a server module) → fail on a pre-existing, unrelated hostId
    placeholder assertion from `hosts/server-amd.nix:15`, confirmed untouched by
    `git diff --name-only`; identical failure was present before this change
    (same assertion seen in the prior justfile-only review). Not caused by this
    diff.
- `git ls-files hardware-configuration.nix` → empty (not tracked). ✓
- `stateVersion` unchanged (no `configuration-*.nix` touched). ✓
- No new flake inputs. ✓

## Score table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 100% | A |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 100%* | A |

\* Desktop variants fully evaluate. Server variants blocked by a pre-existing,
out-of-scope hostId placeholder unrelated to this change.

## Result: PASS
