# Review: Install-Time Kernel Fallback

**Date:** 2026-06-09
**Reviewer:** Orchestrating Agent
**Modified files:** `scripts/install.sh`, `template/etc-nixos-flake.nix`, `modules/nix.nix`

---

## Score Table

| Category | Score | Grade |
|---|---|---|
| Specification Compliance | 100% | A |
| Best Practices | 97% | A |
| Functionality | 100% | A |
| Code Quality | 97% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 90% | A- |

**Overall Grade: A (98%)**

---

## Build Validation

- `nix flake show --impure` — **PASS** (flake structure valid, all nixosModules listed)
- `nix-instantiate --parse modules/nix.nix` — **PASS**
- `nix-instantiate --parse template/etc-nixos-flake.nix` — **PASS**
- `bash -n scripts/install.sh` — **PASS**
- `sudo nixos-rebuild dry-build` — **NOT RUN** (sudo unavailable in sandbox; requires NixOS host)
- `git ls-files hardware-configuration.nix` — **PASS** (empty output, not committed)
- `system.stateVersion` check — **PASS** (unchanged at "25.11" in all configuration-*.nix files)
- New flake inputs — **N/A** (no new inputs added)

Build score reflects that dry-build validation was not runnable in this environment. Nix parse checks passed for all modified Nix files.

---

## Findings

### Specification Compliance — PASS
All three implementation steps from the spec were delivered:
- `template/etc-nixos-flake.nix`: `kernelOverrideFile` / `hasKernelOverride` added to `let` block; `lib.optional hasKernelOverride kernelOverrideFile` appended to `_mkVariantWith` (desktop only) ✓
- `scripts/install.sh`: kernel-dep-only classification + fallback + re-verification + post-install notice ✓
- `modules/nix.nix`: override auto-clear check in `vexos-update` before `flake update` ✓

### Best Practices — PASS
- `lib.mkForce` used correctly to override `boot.kernelPackages` set at priority 100 in `system-desktop-kernel.nix` ✓
- `builtins.pathExists` pattern matches the existing `server-services.nix` and `stateless-user-override.nix` opt-in patterns ✓
- Heredoc inside `writeShellScriptBin` replaced with `printf '%s\n'` to avoid ambiguity in Nix `''` strings ✓
- `bash -n` passes: no syntax errors ✓

### Consistency — PASS
- Module Architecture Pattern (Option B) not violated — no `lib.mkIf` guards added to shared modules ✓
- Override file is an additive opt-in module, never imported unconditionally ✓
- `HEAVY_BUILD_REGEX` in install script uses a shorter form than vexos-update's (no `linux-[0-9]` kernel modules since the SOURCE_BUILDS filter already excludes `linux-[0-9]` derivations) — intentional and correct ✓

### Security — PASS
- Override file written via `sudo tee` (install script runs as user with sudo) and `printf >` (vexos-update runs as root via sudo) — both correct for `/etc/nixos/` writes ✓
- No hardcoded secrets, no world-writable paths, no credential assignments ✓
- Override file content is static Nix with no interpolation ✓

### Minor observations (non-blocking)
- The `vexos-update` override check uses the current pinned flake revision (pre-update), which is the correct behavior — checks the actual state before bumping inputs.
- The `ROLE = "desktop"` guard in install.sh is correct: other roles use LTS kernels (always cached) and their template builders don't include the override file anyway. Double-guard provides defence in depth.

---

## Result: PASS
