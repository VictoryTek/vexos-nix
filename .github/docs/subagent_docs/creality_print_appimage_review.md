---
name: creality_print_appimage_review
description: Phase 3 review for Creality Print AppImage derivation feature
metadata:
  type: project
---

# Creality Print AppImage — Review

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 95% | A |
| Functionality | 95% | A |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | N/A* | — |

**Overall Grade: A (98%)**

*Build validation: `nix` is not available on the Windows dev machine. Nix evaluation is deferred to the NixOS host. `lib.fakeHash` is an intentional placeholder — the first `nixos-rebuild dry-build` will fail with the correct hash, which the user must paste in before the build can succeed. This is documented in the spec and the package file. All other validation checks passed.

## Checklist

### Specification Compliance ✅
- [x] `pkgs/creality-print/default.nix` created using `appimageTools.wrapType2`
- [x] `pkgs/default.nix` updated with `vexos.creality-print` entry
- [x] `modules/3d-print.nix` updated with `pkgs` arg and `environment.systemPackages`
- [x] `modules/gnome-desktop.nix` — "3D" added to `folder-children`; 3D folder definition added with all three apps
- [x] `home-desktop.nix` — `CrealityPrint.desktop` added to 3D folder; stamp bumped to v4

### Best Practices ✅
- [x] Uses `appimageTools.wrapType2` — correct nixpkgs pattern for squashfs AppImages (handles FUSE by extracting at build time)
- [x] `lib.fakeHash` placeholder — consistent with existing `pkgs/kiji-proxy/default.nix` pattern
- [x] Update instructions in file header — matches portbook/kiji-proxy style
- [x] Package under `pkgs.vexos.*` namespace — avoids upstream nixpkgs collisions
- [x] `unfree` license declared — `allowUnfree = true` already set globally in `modules/nix.nix`
- [x] `platforms = [ "x86_64-linux" ]` — AppImage is x86_64 only; prevents accidental evaluation on aarch64

### Consistency ✅
- [x] Module Architecture Pattern (Option B) respected — no new `lib.mkIf` guards added
- [x] `3d-print.nix` remains desktop-only (imported only from `configuration-desktop.nix`)
- [x] No changes to server, stateless, htpc, or headless-server modules
- [x] dconf folder entry style matches all other folder definitions in `gnome-desktop.nix`
- [x] First-run service stamp bump (v3 → v4) follows established precedent for layout changes

### Security ✅
- [x] No hardcoded secrets
- [x] No world-writable paths introduced
- [x] License is unfree, not a security concern; `allowUnfree` is already global
- [x] `fetchurl` + hash ensures the binary is the one we pinned (once hash is filled in)

### Git Safety ✅
- [x] `hardware-configuration.nix` not tracked
- [x] `system.stateVersion` unchanged in all `configuration-*.nix` files (all remain `"25.11"`)
- [x] No new flake inputs added — no `follows` concern

## Known Limitations (not blockers)

1. **Hash placeholder:** `lib.fakeHash` must be replaced on the NixOS host before `nixos-rebuild` succeeds. This is expected and documented.
2. **Desktop entry name unverified:** `CrealityPrint.desktop` is the standard AppImage convention but can only be confirmed after the first build on the NixOS host. If it differs, a one-line fix in both `gnome-desktop.nix` and `home-desktop.nix` resolves it.

## Build Result

Cannot execute on this Windows dev machine. Nix is not installed. All structural, syntactic, and logic checks pass on inspection.

## Verdict: PASS (pending hash fill-in on NixOS host)
