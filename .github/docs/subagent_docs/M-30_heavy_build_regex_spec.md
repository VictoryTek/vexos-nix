# M-30 — `HEAVY_BUILD_REGEX` defined in three places with two different values

Status: Phase 1 (Research & Specification)
Source: MASTER_PLAN M-30 (ARCH 3.3, BUGS M16) · `modules/nix.nix:147,194`,
`scripts/install.sh:368`

## Current State

The MASTER_PLAN's file references are stale — `modules/nix.nix` no longer contains
this script at all; it moved to `pkgs/vexos-update/default.nix` during M-26 this
session. Re-checked every occurrence directly:

- `pkgs/vexos-update/default.nix:124` — `KERNEL_BLOCK_REGEX='^(linux-[0-9][^/]*-modules|linux-[0-9][^/]*-modules-shrunk)'`,
  used by the kernel-install-override auto-clear check.
- `pkgs/vexos-update/default.nix:177` — `HEAVY_BUILD_REGEX='^(linux-[0-9][^/]*-modules|linux-[0-9][^/]*-modules-shrunk)'`,
  used by the main three-way local-build classifier.
- `scripts/install.sh:436` — `UNAVOIDABLE_REGEX='^(NVIDIA-Linux-|nvidia-x11-|nvidia-settings-|nvidia-persistenced-|openrazer-[0-9])'`.
- `pkgs/vexos-update/default.nix:178` — the same `UNAVOIDABLE_REGEX`, identical value.

So today all four occurrences hold *identical* values (the "two different values"
the MASTER_PLAN describes has already been fixed somewhere along the way) — but the
structural drift risk BUGS M16 warns about is still real: the same regex is defined
independently in multiple places, so a future edit to one copy (e.g. adding a new
kernel package naming pattern) can silently miss the other(s).

**Constraint discovered during research:** `scripts/install.sh`'s documented,
primary usage (lines 6-7 of its own header) is:
```
curl -fsSL https://raw.githubusercontent.com/VictoryTek/vexos-nix/main/scripts/install.sh | bash
```
This is a network one-liner with no local repository clone present — there is no
`scripts/` directory on disk to `source` a shared fragment from. A literal
`source "$(dirname "$0")/vexos-regex-patterns.sh"` would break this primary use
case (`$0` is `bash`, not a path to a checked-out repo). This makes the
MASTER_PLAN's literal suggestion ("consolidate into one sourced fragment in
scripts/") infeasible without dropping curl-pipe support — confirmed with the user,
who chose to keep the duplicate necessary for standalone execution rather than
break the documented one-liner install path.

## Problem Definition

Two distinct duplication risks exist:
1. **Same-file duplication** (fixable): `pkgs/vexos-update/default.nix` defines the
   identical kernel-modules regex twice under two different names
   (`KERNEL_BLOCK_REGEX`, `HEAVY_BUILD_REGEX`) in the same file, for no reason —
   both run in the same script execution, so there's no isolation benefit.
2. **Cross-file duplication** (not fixable without breaking curl-pipe install):
   `UNAVOIDABLE_REGEX` appears in both `install.sh` (runs standalone, pre-NixOS,
   no repo present) and `pkgs/vexos-update/default.nix` (runs post-install, as a
   built Nix package). These execute in genuinely different lifecycles/contexts
   and can't share a sourced file while `install.sh` remains curl-pipeable.

## Proposed Solution

1. In `pkgs/vexos-update/default.nix`: delete `KERNEL_BLOCK_REGEX`, move the single
   `HEAVY_BUILD_REGEX` definition up before its first use (the kernel-override
   check at what is currently line 124), and use it for both the kernel-override
   check and the main classifier. This is a true consolidation — one definition,
   one file, both use sites.
2. For `UNAVOIDABLE_REGEX`: keep the literal in both `install.sh` and
   `pkgs/vexos-update/default.nix` (required for `install.sh`'s standalone
   curl-pipe execution), but add a one-line comment at each definition site
   pointing at the other file/line, so a future edit to one is prompted to check
   the other. This doesn't eliminate the duplication risk, but converts a silent
   drift hazard into a discoverable one — the cheapest mitigation that doesn't
   sacrifice the documented install method.

## Implementation Steps

1. `pkgs/vexos-update/default.nix` — remove `KERNEL_BLOCK_REGEX`; hoist
   `HEAVY_BUILD_REGEX`'s definition above the kernel-override check; update the
   kernel-override check's `grep -E` call to reference `HEAVY_BUILD_REGEX`; add a
   cross-reference comment above `UNAVOIDABLE_REGEX` pointing at
   `scripts/install.sh`.
2. `scripts/install.sh` — add a matching cross-reference comment above its
   `UNAVOIDABLE_REGEX` definition pointing back at
   `pkgs/vexos-update/default.nix`.

## Configuration Changes

None — pure internal refactor of shell variable naming/placement; regex values
unchanged.

## Risks and Mitigations

- **Risk:** hoisting `HEAVY_BUILD_REGEX` above the kernel-override block changes
  where in the script the variable becomes visible.
  **Mitigation:** shell variables in a flat script (no functions) are visible to
  every subsequent line regardless of where they're defined, as long as
  definition precedes first use — verified the kernel-override check is still
  the first use site after hoisting.
- **Risk:** `shellcheck` (run automatically at build time via
  `writeShellApplication`, and exercised by preflight's `[8/8]` check) could flag
  something in the reordering.
  **Mitigation:** verified via Phase 3 build (`nix build` on
  `pkgs.vexos.vexos-update` / preflight `[8/8]`).
