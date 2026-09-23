# Arcane `appUrl` auto-default — Phase 3 Review

## Scope Reviewed

- `modules/server/arcane.nix`
- `justfile` (`enable service` recipe, Arcane-specific block)
- `template/server-services.nix`

Against spec: `arcane_appurl_autodefault_spec.md`.

## 1. Specification Compliance

Matches spec exactly:
- `appUrl` default changed from invalid placeholder to
  `"http://localhost:${toString cfg.port}"`.
- The `appUrl != placeholder` assertion removed.
- Header doc comment's "Required configuration" no longer lists `appUrl`.
- `justfile`'s interactive `read -r -p` block for Arcane's URL removed;
  comment above the Arcane block updated to explain the new behavior.
- `environmentFile` auto-generation (untouched, matches SearXNG/VexBoard
  pattern) left exactly as-is, per spec.
- `template/server-services.nix` comment updated to mark `appUrl` optional.

## 2. Best Practices / Consistency (Module Architecture Pattern)

`modules/server/arcane.nix` remains a role-addition file with no new
`lib.mkIf` role/display/gaming guards — this was a same-module
option-default and assertion change, not a module-boundary change. No
architecture-pattern violation introduced.

## 3. Completeness

All three assertion-driving/user-facing touchpoints for `appUrl` (module
default+assertion, justfile interactive prompt, template example comment)
were updated consistently — no stale reference to the old placeholder or
the old "must be supplied" requirement remains (verified via grep).

## 4. Security

`environmentFile` requirement (ENCRYPTION_KEY/JWT_SECRET) — the actual
security-relevant assertion — is untouched. `appUrl` was never
security-enforcing; it only affects link construction. No new secrets,
no plaintext credentials introduced.

## 5. API Currency (Context7 — `/getarcaneapp/arcane`)

Verified against Arcane's own `.env.example` / `_autodocs/configuration.md`:
`APP_URL` is a link/redirect/OIDC-callback/CORS convenience setting, not a
network-exposure or listen-address setting. A `localhost`-based default is
functionally safe for the default (non-reverse-proxied, non-OIDC) deployment
this project ships out of the box.

## 6. Build Validation

- `nix flake show --impure` — **PASS** (structure evaluates cleanly).
- `git ls-files hardware-configuration.nix` — empty, **PASS**.
- `system.stateVersion` — unchanged in all 6 `configuration-*.nix` files,
  **PASS**.
- No new flake inputs added — `follows` check N/A.
- `just --list` — parses cleanly, no syntax errors from the justfile edit.
- `grep` for leftover `ARCANE_URL_OPTION`/removed-code references — none
  found outside the updated comment.

### Environment constraint — dry-build substitution (disclosed, not silently skipped)

This session's Bash sandbox has no working `sudo` (`sudo: the "no new
privileges" flag is set, which prevents sudo from running as root` — true
even with the sandbox-disable option). `sudo nixos-rebuild dry-build
--flake .#vexos-server-amd` / `--flake .#vexos-headless-server-amd`, as
specified for server-module changes, could **not** be executed as literally
written. Rather than skip validation, this was substituted with:

1. `nix eval --impure ".#nixosConfigurations.vexos-server-amd.config.system.build.toplevel.drvPath"`
   — the CI-equivalent method this repo's own `.github/workflows/ci.yml`
   uses for full-closure evaluation. This surfaced a **pre-existing,
   unrelated** failure: the ZFS `networking.hostId` placeholder assertion in
   `hosts/server-amd.nix` (`lib.mkDefault "a0000001"`), which CI works
   around with a stub `hardware-configuration.nix` fixture written via
   `sudo`. That workaround also requires root and was not reproducible here
   (`/etc/nixos/hardware-configuration.nix` is owned by `root:root`, not
   writable by this session's user).
2. To isolate the Arcane change from that unrelated, pre-existing gate:
   `nix eval --impure` against
   `nixosConfigurations.vexos-server-amd.extendModules { modules = [{
   vexos.server.arcane.enable = true; vexos.server.arcane.environmentFile =
   "/tmp/fake-env"; }]; }`, checking `config.assertions` directly. With
   Arcane force-enabled, **the only failing assertion in the entire
   evaluated config is the pre-existing ZFS hostId one** — nothing from
   `arcane.nix`. `config...containers.arcane.environment.APP_URL` resolves
   to `http://localhost:3552` with no eval errors.
   `options.vexos.server.arcane.appUrl.default` also evaluates cleanly on
   its own (confirms the `${toString cfg.port}` interpolation is valid).
3. `git status --short` confirms `hosts/server-amd.nix` was not touched by
   this change — the hostId failure predates and is unrelated to it.

This is evaluation-level validation (assertions, types, option merging),
not a full derivation build/realization — same depth `nix eval
--impure...drvPath` gives in CI, short of the final `nixos-rebuild
switch`/`boot` step this project explicitly reserves for the user. The
one CLAUDE.md-mandated step not literally executed is the `sudo
nixos-rebuild dry-build` invocation itself, due to this session's sandbox
lacking root — disclosed here rather than asserted as passed.

- `scripts/preflight.sh` (Phase 6, run ahead for early signal) — **exit 0,
  "Preflight PASSED — safe to push."** Its own dry-build stage (`nix build
  --dry-run`, which needs no root) targeted this dev machine's own variant
  (`vexos-desktop-nvidia`) and passed. Two pre-existing WARNs unrelated to
  this change: repo-wide `nixpkgs-fmt` formatting debt (114/204 files,
  predates this change) and a placeholder-string false-positive in
  `modules/server/vexboard.nix` (`"change-me-set-vexos.server.vexboard.secretFile"`).
  Neither blocks preflight (WARN, not HARD fail) and neither is in a file
  this change touched.

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
| Build Success | 90% | A- |

**Overall Grade: A (98%)**

Build Success is marked 90% (A-) purely because the literal `sudo
nixos-rebuild dry-build` command could not run in this sandbox (no root) —
not because any check failed. Every substitute check that could run,
including ones purpose-built to isolate this change from a pre-existing,
unrelated assertion failure, passed.

## Verdict

**PASS.**
