# STATELESS_VM_HYPERVISOR — Review

## Phase 3: Review & Quality Assurance

### Scope reviewed

| File | Change |
|------|--------|
| `scripts/stateless-setup.sh` | Hypervisor prompt (vm only); summary line; write + persist `vm-platform.nix` for VirtualBox |
| `scripts/migrate-to-stateless.sh` | Hypervisor prompt (vm only); write + `git add` + persist `vm-platform.nix` for VirtualBox |
| `flake.nix` | New `statelessVmPlatformModule`; added to `roles.stateless.hostLocalModules` |
| `template/etc-nixos-flake.nix` | New `vmPlatformFile` / `hasVmPlatform`; `mkStatelessVariant` imports it |
| `.github/docs/subagent_docs/STATELESS_VM_HYPERVISOR_spec.md` | Phase 1 spec |

`justfile` and `template/features.nix`: unchanged (mid-implementation edits reverted
after the mechanism pivot).

### 1. Specification compliance

Matches the spec as revised. The spec's original approach (wire `features.nix` into
stateless) was implemented, evaluated, found to break `vexos-stateless-vm` on hosts
with a populated `features.nix` (`The option 'vexos.features' does not exist`), and
replaced with a dedicated `vm-platform.nix`. Spec Decision section and steps updated
to record this.

### 2. Best practices

- New flake module follows the existing `statelessUserOverrideModule` idiom exactly
  (`builtins.pathExists` → singleton or empty list).
- Template follows the sibling `hasUserOverride` / `userOverrideFile` idiom.
- `vexos.vm.platform` remains a module-declared toggle gated inside
  `modules/gpu/vm-guest-additions.nix` — no new `lib.mkIf`, no role-smuggling.
- Prompt wording and `case` arms copied verbatim from `install.sh:541-556`.

### 3. Consistency (Module Architecture Pattern — Option B)

Compliant. No conditional logic added to shared modules. The stateless role
continues to express itself through its import list; the new file is an optional
host-local import, same class as `stateless-user-override.nix`.

### 4. Maintainability

`vm-platform.nix` has a self-describing header naming the writer script. Flake and
template carry comments explaining why it is separate from `features.nix`. Spec
records the rejected alternative so the decision is not re-litigated.

### 5. Completeness

- Live-ISO install path: `stateless-setup.sh` ✓
- In-place migration path: `migrate-to-stateless.sh` ✓
- Repo flake (`nixos-rebuild switch` from a checkout / migration): `flake.nix` ✓
- Template flake (fresh `nixos-install`): `template/etc-nixos-flake.nix` ✓
- Persistence across impermanence wipe: both copy lists ✓
- Git tracking for `git+file://`: `git add .` (setup) / explicit `git add` (migrate) ✓

### 6. Performance

No evaluation-time cost when the file is absent (one `pathExists`, already the
pattern for four other optional files). No CI impact — absent in the CI sandbox.

### 7. Security

`vm-platform.nix` contains a single non-secret enum assignment. Written with the
default umask (world-readable) — correct and matching `install.sh`'s `features.nix`;
no tightening needed (contrast `stateless-user-override.nix`, chmod 0600 for its
password hash). No new world-writable files, no credentials.

### 8. API currency

No external libraries. `vexos.vm.platform` is an in-repo option; usage verified
against `modules/gpu/vm-guest-additions.nix`.

### 9. Build validation

| Check | Result |
|-------|--------|
| `bash -n scripts/stateless-setup.sh` | ✓ pass |
| `bash -n scripts/migrate-to-stateless.sh` | ✓ pass |
| `shellcheck -S warning` (both scripts, shellcheck 0.11.0) | ✓ clean, exit 0 |
| `nix-instantiate --parse flake.nix` | ✓ pass |
| `nix-instantiate --parse template/etc-nixos-flake.nix` | ✓ pass |
| `nix flake show --impure` | ✓ 30 nixosConfigurations, unchanged |
| `nix eval .#nixosConfigurations.vexos-stateless-vm.…toplevel.drvPath` | ✓ produces drvPath (was failing under the reverted features.nix approach) |
| `nix eval …vexos-stateless-vm.config.vexos.vm.platform` | ✓ `"qemu"` (option wired, default intact) |
| `nix eval …vexos-stateless-vm.options.vexos.vm.platform.type.description` | ✓ `one of "qemu", "virtualbox"` |
| `git ls-files hardware-configuration.nix` | ✓ empty (not tracked) |
| `system.stateVersion` in all 6 `configuration-*.nix` | ✓ present, unchanged |
| New flake inputs | none added |

Full VirtualBox-path eval (temp `/etc/nixos/vm-platform.nix` → 6.18 kernel pin)
could not be run here — sandbox denies `sudo` writes to `/etc/nixos`. The wiring is
byte-for-byte the same pattern as the working `statelessUserOverrideModule` /
`hasUserOverride` imports, and the option is confirmed present on the stateless-vm
config. Deferred to the user's own host or CI.

### Findings

None CRITICAL. None RECOMMENDED outstanding.

### Score table

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

### Result

**PASS** — proceed to Phase 6 (Preflight).
