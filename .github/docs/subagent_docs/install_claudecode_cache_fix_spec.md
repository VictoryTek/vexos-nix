# Spec: Exclude claude-code from install cache check

## Current State Analysis

`scripts/install.sh` lines 356–360 contain a `grep -Ev` exclusion regex that filters
out derivation names known to be false positives in the binary cache check. Currently
it excludes Electron/Node packages via patterns like `vscode-`, `nodejs-`, and `code-[0-9]`.

The pattern `code-[0-9]` only matches packages whose name starts with `code-` followed
immediately by a digit (e.g. `code-1.99.0`). It does NOT match `claude-code-2.1.140`.

## Problem Definition

When `nixpkgs-unstable` updates, `claude-code` version numbers advance faster than
Hydra builds them. On a fresh NVIDIA desktop install the cache check sees:

```
NVIDIA-Linux-x86_64-580.142.run.drv  → HEAVY (kernel-dep)
nvidia-x11-580.142-6.18.34.drv       → HEAVY (kernel-dep)
openrazer-3.10.3-6.18.34.drv         → HEAVY (kernel-dep)
nvidia-settings-580.142.drv          → HEAVY (kernel-dep)
claude-code-2.1.140.drv              → NOT in exclusion, NOT in HEAVY
```

`NON_KERNEL_BUILDS` is non-empty due to `claude-code`, so the kernel-fallback branch
(line 371) is not entered, and the install aborts with an unnecessary error.

## Proposed Solution

Add `claude-code-` to the exclusion regex on line 359, alongside `vscode-` and `code-[0-9]`.

`claude-code` is an npm-based package. Its local source build completes in minutes
(not hours), and it updates frequently — the same reasoning that already excludes
`vscode-` applies here.

## Implementation Steps

1. Edit the `grep -Ev` pattern on line 359 of `scripts/install.sh`
2. Append `|claude-code-` inside the existing `(...)` exclusion group

No other files require changes.

## Risks and Mitigations

- **Risk:** Silent local build if claude-code is not cached.
  **Mitigation:** Acceptable — npm builds are fast. Consistent with existing `vscode-` exclusion.
- **Risk:** If a future claude-code package takes hours to build, users won't be warned.
  **Mitigation:** Claude Code is npm-based; this scenario is not realistic.
