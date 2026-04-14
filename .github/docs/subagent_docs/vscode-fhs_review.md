# Review: Fix VS Code Launch Failure on NixOS (vscode-fhs)

**Feature:** `vscode-fhs`  
**Date:** 2026-04-13  
**Reviewer:** Review Subagent  
**Status:** PASS  

---

## 1. Change Verification — `modules/development.nix`

### Modified Line (line 19)

```nix
unstable.vscode-fhs                           # VS Code in FHS env (fixes launch on NixOS)
```

**Confirmed:** The line now reads `unstable.vscode-fhs`. The previous value `unstable.vscode`
is no longer present.

**No accidental changes:** All surrounding lines (Podman config, Python, Rust, TypeScript/Node,
Containers, Flatpak, and General dev utilities sections) are intact and unmodified.

### Minor Comment Deviation

The spec specified the comment as `# VS Code in FHS env (required on NixOS)`.
The implemented comment reads `# VS Code in FHS env (fixes launch on NixOS)`.
This is cosmetically different but semantically equivalent. Not a critical issue.

### Nix Syntax Validity

`unstable.vscode-fhs` uses attribute set dot-access notation. In Nix, hyphenated attribute
names are valid identifiers — `vscode-fhs` is a legal attribute name and is accessible via
`pkgs.vscode-fhs` without quoting. The pattern is identical in form to every other
`unstable.*` usage in the codebase.

---

## 2. Package Validity — `vscode-fhs` in nixpkgs

`vscode-fhs` is a well-established top-level alias for `vscode.fhs` in nixpkgs, defined in
`pkgs/applications/editors/vscode/generic.nix` via `buildFHSEnv`. It is confirmed present in
`nixpkgs-unstable` at version **1.114.0** (as documented in the spec, verified against Context7
and nixpkgs source). The attribute is available via both stable (25.11) and unstable channels.

---

## 3. Flake Input / Overlay Verification

In `flake.nix`, the `unstableOverlayModule` is defined as:

```nix
unstableOverlayModule = {
  nixpkgs.overlays = [
    (final: prev: {
      unstable = import nixpkgs-unstable {
        inherit (final) config;
        inherit (final.stdenv.hostPlatform) system;
      };
    })
  ];
};
```

This module is included in both `commonModules` and `minimalModules`, which means every
`nixosConfigurations` output in the flake receives `pkgs.unstable`. Therefore
`unstable.vscode-fhs` will resolve correctly at evaluation time.

The `nixpkgs-unstable` input is declared at the top of `flake.nix` and deliberately does not
use `follows = "nixpkgs"` (this is intentional and documented in a comment in the flake).

---

## 4. Build Validation

**Environment:** Windows (PowerShell) — NixOS builds cannot be executed.

**Static analysis (no evaluation errors detected):**

| Check | Result |
|-------|--------|
| `unstable.vscode-fhs` attribute access syntax valid | ✔ Pass |
| `unstable` overlay defined and propagated to all modules | ✔ Pass |
| `vscode-fhs` is a known top-level nixpkgs attribute | ✔ Pass |
| No duplicate `vscode` package references found | ✔ Pass |
| Module file is syntactically well-formed (braces/brackets balanced) | ✔ Pass |
| No references to removed or renamed packages introduced | ✔ Pass |

**Note:** Live `nix flake check` and `nixos-rebuild dry-build` could not be executed in this
environment. These must be run on a NixOS host before pushing. Based on static analysis, no
evaluation errors are anticipated.

---

## 5. Safety Checks

| Check | Result |
|-------|--------|
| `hardware-configuration.nix` absent from repo root | ✔ Confirmed (file search returned no matches) |
| `system.stateVersion` unchanged | ✔ Confirmed — `system.stateVersion = "25.11"` in `configuration.nix` line 123 |
| No new flake inputs introduced | ✔ Confirmed — change uses existing `nixpkgs-unstable` input |
| No other files modified | ✔ Confirmed — single-file, single-line change |

---

## 6. Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 98% | A |
| Best Practices | 100% | A+ |
| Functionality | 100% | A+ |
| Code Quality | 100% | A+ |
| Security | 100% | A+ |
| Performance | 100% | A+ |
| Consistency | 100% | A+ |
| Build Success | N/A (Windows) — Static: 100% | A+ |

**Overall Grade: A+ (99.75%)**

---

## 7. Summary

The change is a clean, minimal, correct single-line fix. `unstable.vscode-fhs` is the
canonical NixOS-recommended package for VS Code, wrapping the editor in a `buildFHSEnv`
chroot that resolves all dynamic linker failures caused by NixOS's non-FHS filesystem layout.
The `unstable` overlay is correctly defined in `flake.nix` and propagated to all system
configurations, so the attribute resolves without issue. No safety constraints were violated.

The only deviation from the spec is a cosmetic comment wording difference (`"fixes launch on NixOS"`
vs `"required on NixOS"`), which has no functional impact.

**Verdict: PASS**

---

## 8. Build Result

> Build commands (`nix flake check`, `nixos-rebuild dry-build`) **could not be run** — this
> review was executed in a Windows (PowerShell) environment where NixOS tooling is unavailable.
> Static analysis found no evaluation errors. Live validation must be performed on a NixOS host.
