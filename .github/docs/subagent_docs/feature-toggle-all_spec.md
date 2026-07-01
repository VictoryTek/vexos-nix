# enable-feature/disable-feature "all" — Spec

## Current State Analysis

`justfile:981` (`enable-feature feature:`) and `justfile:1075` (`disable-feature
feature:`) each take a single `feature` argument, validate it against
`_feature_names := "gaming development print3d virtualization"` (`justfile:940`), then
sed-toggle the corresponding `vexos.features.<feature>.enable` line in
`/etc/nixos/features.nix`. Both depend on `_require-desktop-role` (feature toggles are
desktop-role-only).

There is currently no way to enable or disable every feature in one command — a user
must run the recipe once per feature name.

## Problem Definition

Add `just enable-feature all` / `just disable-feature all` that do exactly what the name
says: enable (or disable) every feature in `_feature_names`, using the exact same
per-feature logic already implemented and validated (idempotency checks, template
bootstrap, sed toggling, "already enabled/disabled" messaging) — no new toggle
mechanism, no duplicated logic.

## Proposed Solution

Add an `all` special-case at the top of each recipe body, before the existing
single-feature validation, that loops over `{{_feature_names}}` and re-invokes `just
enable-feature "$f"` / `just disable-feature "$f"` for each name, then exits. This
reuses the existing, already-correct per-feature recipe body verbatim (including
first-run `features.nix` bootstrap from the template, idempotent "already
enabled/disabled" checks, and the existing error handling) rather than re-implementing
any of that logic inline.

## Implementation Steps

1. `justfile` `enable-feature feature:` — add an `if [ "$FEATURE" = "all" ]` branch that
   loops `for f in {{_feature_names}}; do just enable-feature "$f"; done` then exits 0,
   placed before the existing `VALID_FEATURES` unknown-feature check.
2. `justfile` `disable-feature feature:` — identical `all` branch calling `just
   disable-feature "$f"`.
3. Update the one-line usage comments above each recipe
   (`# Enable an optional feature module.  Usage: just enable-feature gaming`) to
   mention `all`.

No changes to `_feature_names`, `_require-desktop-role`, `features.nix`, or any `.nix`
module — this is a justfile-only, additive change.

## Dependencies

None — no new tools, packages, or flake inputs. Context7 not applicable (`just` recipe
syntax, not a versioned library API).

## Configuration Changes

None.

## Risks and Mitigations

- **Risk:** infinite recursion if `all` were matched inside the loop.
  **Mitigation:** the loop iterates over the literal feature names in `_feature_names`
  (`gaming development print3d virtualization`), which never includes the string
  `all`, so each nested `just enable-feature "$f"` call hits the normal, non-`all`
  code path.
- **Risk:** `_require-desktop-role` re-runs once per nested call (4 extra invocations).
  Negligible cost, and correctness-safe (idempotent read-only check).
