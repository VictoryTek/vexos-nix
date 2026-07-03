# H-15 — Review & Quality Assurance

Status: Phase 3 (Review)
Spec: `.github/docs/subagent_docs/H-15_sops_migration_spec.md`

## Modified Files

- `modules/server/vaultwarden.nix` — new `environmentFile` option, wired to
  `services.vaultwarden.environmentFile` (coerced to a list per upstream's
  `coercedTo path lib.singleton (listOf path)` type).
- `modules/server/authelia.nix` — new `jwtSecretFile`, `sessionSecretFile`,
  `storageEncryptionKeyFile` options; container volume mounts + Authelia's native
  `AUTHELIA_*_FILE` env vars, all conditional on the option being set.
- `modules/server/vexboard.nix` — `system.activationScripts.vexboardSecret`, gated to
  the plaintext backend only, generates the secret file via `openssl rand` on first
  activation if missing.
- `modules/secrets-sops.nix` — 8 new `sops.secrets`/`sops.templates` entries (vexboard,
  kiji-proxy, listmonk × 2, vaultwarden, authelia × 3) with matching assertions and
  `lib.mkForce` overrides, following the file's existing pattern exactly.
- `justfile` — new `secrets-init` recipe (age key generation + `.sops.yaml` /
  `sops.secrets` guidance), placed in the Server Services Management section.

## Review Findings

1. **Specification Compliance** — matches the spec exactly: all three sops-ready services
   wired, the two services needing new module options got them, `secrets-init` added,
   VexBoard auto-generation added, code-server explicitly and correctly excluded.
2. **Best Practices** — new options follow this repo's existing option-naming and
   description conventions; sops secrets/templates mirror the file's pre-existing entries
   attribute-for-attribute (owner/group/mode).
3. **Consistency (Module Architecture Pattern)** — no shared/base modules touched; all
   changes are within already-role-scoped `modules/server/*.nix` files or the existing
   `secrets-sops.nix` (itself already gated by `lib.mkIf (cfg.backend == "sops")`, not a
   newly introduced guard). No new `lib.mkIf` added to any shared base module.
4. **Maintainability** — each new option carries a description; the `secrets-init`
   recipe explicitly documents why it doesn't auto-encrypt the secrets file (avoids
   reimplementing sops's own edit workflow).
5. **Completeness** — all items from the spec are implemented.
6. **Performance** — no runtime cost changes (activation script is a no-op after first
   run — file-existence check).
7. **Security** — no hardcoded secrets introduced. Vaultwarden/authelia secret material
   never touches the Nix store (file paths only, consistent with the rest of this
   codebase's plaintext/secretFile pattern). Authelia container mounts are read-only
   (`:ro`). VexBoard's auto-generated secret is written with `chmod 0600`.
8. **API Currency** — `services.vaultwarden.environmentFile` and
   `services.listmonk.secretFile` usage verified directly against the nixpkgs revision
   this flake is pinned to (local `/nix/store` source read, not training-data memory).
9. **Build Validation:**
   - `nix flake show --impure` — passed, all 30 configurations enumerate cleanly.
   - `sudo nixos-rebuild dry-build` is unavailable in this sandboxed session (`sudo`
     blocked by `no new privileges`); substituted with the CI-equivalent safe command
     per CLAUDE.md: `nix eval --impure ".#nixosConfigurations.<x>.config.system.build.toplevel.drvPath"`.
   - `vexos-desktop-amd`, `vexos-desktop-nvidia`, `vexos-desktop-vm` — evaluate cleanly.
   - `vexos-server-amd`, `vexos-headless-server-amd` — evaluate cleanly (required because
     this change touches server modules).
   - Additionally verified the `lib.mkIf (cfg.backend == "sops")` branch itself — which
     is lazy and wasn't forced by the above (none of those hosts default to the sops
     backend) — by evaluating `vexos-server-amd.extendModules` with
     `vexos.secrets.backend = "sops"` and all four newly-wired services
     (vexboard/kiji-proxy/vaultwarden/authelia) enabled. This forced evaluation of every
     new secret, template, and force-override and it built the full `toplevel.drvPath`
     successfully — confirming no typos in attribute names and correct type coercion for
     the new vaultwarden/authelia options.
   - `git ls-files hardware-configuration.nix` — empty (not committed). ✓
   - `system.stateVersion` — no `configuration-*.nix` diff touches it. ✓
   - `flake.nix` — untouched; no new flake inputs, `follows` policy not implicated. ✓
   - `just --list` — justfile parses without error; `secrets-init` appears in the recipe
     list, matching the ungrouped style of its sibling Server Services recipes.

No CRITICAL or RECOMMENDED issues found.

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

- Build result: PASS (all required eval targets green; sops branch force-evaluated separately)
- **PASS**
