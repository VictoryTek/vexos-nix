# proxmox_binary_cache — Review & QA

Spec: `.github/docs/subagent_docs/proxmox_binary_cache_spec.md`

## Modified / Added Files

- `flake.nix` — added top-level `nixConfig` (additive `extra-substituters` / `extra-trusted-public-keys`)
- `modules/nix-proxmox-cache.nix` — new file; appends SaumonNet substituter + key to `nix.settings`
- `configuration-server.nix` — +1 import
- `configuration-headless-server.nix` — +1 import
- `modules/server/proxmox.nix` — comment refresh only (no code change)

## 1. Specification Compliance

All five spec implementation steps implemented exactly as written. No scope added.
`nix-proxmox-cache.nix` contains no `lib.mkIf` / role / flag conditionals — scoping is
via the import list only, per Option B. Not gated on `vexos.server.proxmox.enable`
(spec §2: an unused substituter is harmless; import list already expresses scope).

## 2. Best Practices (Nix / NixOS)

- `nixConfig` uses `extra-` prefixed keys — additive, preserves `cache.nixos.org` and
  daemon defaults. Correct (matches the pattern documented in
  `.github/docs/subagent_docs/bazzite_kernel_vm_review.md:33-34`).
- `nix.settings.substituters` / `trusted-public-keys` are `listOf str`; NixOS merges by
  concatenation, so the new module appends to `modules/nix.nix` with no clobber.
- Public key pins signature verification — an unsigned/mismatched path from the cache is
  rejected, so trusting the substituter URL does not weaken closure integrity.

## 3. Consistency

- New file follows the `modules/<subsystem>-<qualifier>.nix` naming convention
  (`nix.nix` base → `nix-proxmox-cache.nix` addition), alongside the existing
  `nix-server.nix` addition module.
- Import lines placed next to `./modules/nix-server.nix` in both role configs with an
  aligned end-of-line comment, matching surrounding style.

## 4. Maintainability

- Both the new module header and the `flake.nix` comment explain *why* (proxmox-nixos
  does not follow nixpkgs → source builds) and the install-time vs running-system split.
- `modules/server/proxmox.nix` comment updated from a stale manual instruction to a
  pointer at the two real locations — removes drift risk.

## 5. Completeness

Covers both failure surfaces: install-time first `nixos-rebuild boot` (nixConfig) and
every subsequent rebuild / non-flake op on server + headless-server (system module).
Immediate operator unblock documented in the spec's risk table.

## 6. Performance

Server rebuilds gain one substituter, queried after `cache.nixos.org`. Non-server roles
are unaffected (module not imported). Net effect is a large reduction in build work when
the SaumonNet cache has the pinned rev's closures.

## 7. Security

- No secrets. The Ed25519 public key is non-secret and was already committed verbatim in
  repo comments.
- No world-writable files, no plaintext credentials.
- Third-party substituter trust is bounded by the pinned public key and consistent with
  the repo's single-operator homelab posture (`modules/nix.nix:131-138`).

## 8. API Currency

N/A — Nix daemon configuration, not an external versioned library. Cache URL + key are
those published by the already-pinned `proxmox-nixos` input.

## 9. Build Validation

| Step | Result |
|------|--------|
| `nix flake show --impure` (WSL, Nix 2.34.1) | PASS — all 30 outputs + nixosModules listed, exit 0. Only pre-existing `kernel-override` "not a derivation" warnings (unrelated). |
| `nix eval path:.#…vexos-headless-server-amd…toplevel.drvPath` | PASS — evaluates to a `.drv` (full module eval incl. assertions), exit 0 |
| `nix eval path:.#…vexos-server-amd…toplevel.drvPath` | PASS — evaluates to a `.drv`, exit 0 |
| Substituter scoping | PASS — `vexos-server-amd` `nix.settings.substituters` contains `https://cache.saumon.network/proxmox-nixos`; `vexos-desktop-amd` does **not** |
| `git ls-files hardware-configuration.nix` | PASS — empty |
| `system.stateVersion` unchanged in all `configuration-*.nix` | PASS — not touched |
| New flake inputs declare `follows` | N/A — no new inputs |

`sudo nixos-rebuild dry-build` not runnable (no NixOS host; Windows + WSL-non-NixOS dev
environment). Full multi-variant dry-build delegated to GitHub Actions CI per the
project's Resource Constraints.

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 95% | A |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 100% | A |

**Overall Grade: A (99%)**

## Phase 6 — Preflight

`bash scripts/preflight.sh` (WSL, Nix 2.34.1, with `nix shell nixpkgs#jq nixpkgs#nixpkgs-fmt`):
**exit 0 — "Preflight PASSED — safe to push."**

- `[1/8]` flake structure + CI-matrix coverage: PASS (no outputs added/renamed).
- `[2/8]` dry-build: SKIP (no NixOS host / `/etc/nixos/vexos-variant`) — delegated to CI.
- `[3/8]` `hardware-configuration.nix` not tracked: PASS.
- `[4/8]` `system.stateVersion` in all 6 configs: PASS (untouched).
- `[5/8]` `flake.lock` committed/pinned/fresh: PASS.
- `[6/8]` Nix formatting: WARN only (non-blocking). 101/193 files "would reformat" —
  a **pre-existing repo-wide** condition; `modules/nix.nix` and `modules/nix-server.nix`
  fail the same check untouched. New file matches the surrounding aligned-`=` style
  (CLAUDE.md §3). No regression.
- `[7/8]` secret scan: WARN on pre-existing `modules/server/vexboard.nix:90` placeholder
  (unrelated to this change).
- `[8/8]` `pkgs.vexos.vexos-update` build + shellcheck: PASS.

## Result

PASS. No CRITICAL issues. Phase 3 review + Phase 6 preflight both green. Both server configs evaluate to a system derivation with the
new module merged; scoping verified (server yes, desktop no).

### Note for delivery (not a code defect)

`modules/nix-proxmox-cache.nix` is a new file. Nix flakes only see git-tracked files, so
it must be `git add`-ed before `flake.nix` can reference it — otherwise `nixos-rebuild`,
`preflight.sh`, and CI fail with `path '.../modules/nix-proxmox-cache.nix' does not exist`.
Staging is the user's responsibility (Phase 7).
