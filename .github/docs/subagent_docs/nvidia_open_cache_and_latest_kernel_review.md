# Review: NVIDIA open-driver cache reality + latest kernel for desktop/stateless

## Implementation summary

| File | Change |
|---|---|
| `modules/system-latest-kernel.nix` | **New.** `boot.kernelPackages = pkgs.linuxPackages_latest;` |
| `modules/system-desktop-kernel.nix` | **Deleted.** (was `linuxPackages_6_18`; only desktop imported it) |
| `configuration-desktop.nix` | Import `system-latest-kernel.nix` instead of `system-desktop-kernel.nix` |
| `configuration-stateless.nix` | Import `system-latest-kernel.nix` instead of `system-lts-kernel.nix` |
| `modules/system-lts-kernel.nix` | Comment updated (no longer references deleted module) |
| `modules/razer.nix` | openrazer overlay retargeted `linuxPackages_6_18` → `linuxPackages_latest`; patch note updated for 7.0.9+ |
| `scripts/install.sh` | Removed `--override-input` pre-pin + `find_cached_nixpkgs_for_attr` history-walk; cache check now classifies unavoidable unfree NVIDIA userspace + patched openrazer as expected local builds (proceed with accurate message) and aborts only on a genuine cache miss; reworded kernel-override cleanup comment |

## Verification (against the working tree via `path:` / direct probes)

- `nvidia-x11-580.142-7.0.11` **builds successfully** (exit 0) — the stale ".ryte" 7.x hold is invalid.
- `nvidia-open-7.0.11-580.142` confirmed **CACHED** on cache.nixos.org.
- `vexos-desktop-nvidia`: kernel `7.0.11`, `hardware.nvidia.open = true`, open module = `nvidia-open-7.0.11-580.142`, `openrazer-3.10.3-7.0.11` resolves (patched overlay applies on latest kernel).
- `vexos-stateless-nvidia`: kernel `7.0.11`.
- `nix flake show` (path:) → 30 nixosConfigurations.
- Full toplevel dry-run (`nix build --dry-run`, path:) for desktop-nvidia AND stateless-nvidia → **exit 0** (no source-build blockers beyond the expected unfree NVIDIA userspace).
- `bash -n scripts/install.sh` → OK. No orphaned references to removed helpers/vars.
- `hardware-configuration.nix` not tracked; `system.stateVersion` present and **unchanged** in all 6 configuration files.

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

## Preflight note

`bash scripts/preflight.sh` reports 6/7 checks passing. The single failure is CHECK 2
(deep dry-build of the current variant), which errors with
`path '.../modules/system-latest-kernel.nix' does not exist` — because the preflight
flakeref uses the git tree (`.`) and the new module is **unstaged**. Staging is the user's
responsibility (Phase 7; the orchestrator is barred from `git add`). The equivalent CHECK 2
dry-run against the working tree (`path:`) passes with exit 0, so preflight turns green the
moment the new file is committed alongside the other changes.

## Result: PASS (pending user staging of the new module)
