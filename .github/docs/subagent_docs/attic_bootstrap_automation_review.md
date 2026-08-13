# Attic Bootstrap Automation — Review

## Spec Reference
`.github/docs/subagent_docs/attic_bootstrap_automation_spec.md`

## Modified Files
- `modules/server/attic.nix`
- `justfile`

## Findings

### 1. Specification Compliance
Implementation matches the spec exactly: activation script mirrors
`vexboardSecret`'s guard/idempotency pattern, `attic-client` added to
`environment.systemPackages`, `attic-bootstrap` recipe added to the Binary
Cache group with the documented preconditions/output, and both guidance
comment blocks updated. No scope creep beyond the spec's four implementation
steps.

### 2. Best Practices (Nix/NixOS)
- Activation script correctly scoped inside `config = lib.mkIf cfg.enable`,
  so it only exists when Attic is enabled.
- Uses `${pkgs.openssl}/bin/openssl` and `${pkgs.coreutils}/bin/base64`
  (absolute store paths) rather than relying on PATH — matches
  `vexboardSecret`'s existing convention exactly.
- `lib.mkIf (config.vexos.secrets.backend != "sops")` correctly reuses the
  cross-module option rather than duplicating logic.

### 3. Consistency / Module Architecture Pattern (Option B)
New content lives entirely inside `lib.mkIf cfg.enable`, an option this same
module (`modules/server/attic.nix`) declares — this is the documented
carve-out (toggleable-subsystem guard), not role-smuggling. No new `lib.mkIf`
guards by role/display/gaming flag were introduced. No new module file was
needed since this is purely additive content for the module's own `enable`
flag, matching how `vexboard.nix` already does it.

### 4. Maintainability
Comments explain *why* (mirrors vexboard pattern, sops backend skip) rather
than restating what the code does. Header comment kept in sync with new
behavior.

### 5. Completeness
All four spec implementation steps present. `just attic-bootstrap` covers
cache creation (idempotent, checked via `attic cache info` before creating),
public key retrieval, and CI token minting, matching spec section 3.

### 6. Performance
RSA key generation happens once, only on first activation when the file is
absent — same cost profile as the existing manual step, just automated.

### 7. Security
- Generated secret file written with `chmod 0600` before any other process
  could read it; matches `vexboard.nix`'s existing pattern.
- No secrets hardcoded; nothing printed to build logs (activation script
  redirects openssl stderr, only writes to the target file).
- `attic-bootstrap`'s printed admin/CI tokens are inherent to the CLI's
  design (same exposure as the pre-existing manual workflow) — not a
  regression.
- Push token deliberately scoped to `--push <cache>` only (not `--pull`/
  `--delete`/`--create-cache`), per spec's least-privilege intent for CI.

### 8. API Currency
`atticd-atticadm` wrapper behavior, `attic cache info` output format, and
`atticadm make-token` flags were verified against upstream
`nixos/atticd.nix` and `docs.attic.rs/tutorial.html` before implementation
(see spec's Current State Analysis). No deprecated patterns used.

### 9. Build Validation
- `nix flake show --impure`: **PASS** — full output enumerated, no errors.
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd|nvidia|vm`: could
  not run — this sandboxed environment has no privilege escalation (`sudo:
  the "no new privileges" flag is set`). Used the documented equivalent
  instead: `nix eval --impure
  ".#nixosConfigurations.vexos-desktop-amd.config.system.build.toplevel.drvPath"`
  → **PASS**, produced a valid `.drv` path, meaning the full module set
  (including the new attic.nix content, via `modules/server` import chain)
  evaluates and composes without error.
- Server-role check (required — this change touches `modules/server/attic.nix`):
  `nix eval --impure` on `vexos-server-amd` and `vexos-headless-server-amd`
  failed, but on a **pre-existing, unrelated** assertion: a shared
  `networking.hostId` ZFS placeholder committed in `hosts/server-amd.nix` /
  `hosts/headless-server-amd.nix` (neither file is part of this diff —
  confirmed via `git diff --stat` showing only `justfile` and
  `modules/server/attic.nix` changed). The error trace does not reference
  `attic.nix`. This is a repository condition that predates and is
  independent of this change.
- `git ls-files hardware-configuration.nix`: empty — not tracked. **PASS**.
- `system.stateVersion`: no `configuration-*.nix` file touched by this diff — **PASS** (unchanged).
- No new flake inputs added — `follows` check N/A.
- `justfile` syntax: `just --list` succeeds — **PASS**.

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 95% | A (logic verified by inspection + upstream doc cross-check; live atticd/attic CLI run not possible in this environment) |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 95% | A (desktop role fully verified; server-role verification blocked only by a pre-existing, unrelated repo assertion, not this change) |

**Overall Grade: A (99%)**

## Result: PASS
