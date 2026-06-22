# Specification: vexboard follows nixpkgs-unstable

Feature name: `vexboard_nixpkgs_unstable_follows`
Spec path: `.github/docs/subagent_docs/vexboard_nixpkgs_unstable_follows_spec.md`
Date: 2026-06-22

---

## 1) Current state analysis

### 1.1 Relevant flake inputs

From `flake.nix`:

```nix
# Up follows the outer stable nixpkgs — so it updates daily when nix flake update runs:
up = {
  url = "github:VictoryTek/Up";
  inputs.nixpkgs.follows = "nixpkgs";
};

# vexboard: pinned to its own independent nixpkgs_3 node (nixos-unstable at a fixed rev):
# Do NOT add inputs.vexboard.inputs.nixpkgs.follows = "nixpkgs" — vexboard builds
# against nixos-unstable with rust-overlay; forcing stable nixpkgs breaks the
# Rust/WASM toolchain.
vexboard.url = "github:VictoryTek/vexboard";
```

From `flake.lock` (lock graph):

- `vexboard.inputs.nixpkgs = "nixpkgs_3"` — an independent node
- `nixpkgs_3.original.ref = "nixos-unstable"` — correct channel, but pinned to a specific rev
- `up.inputs.nixpkgs = ["nixpkgs"]` — follows the outer flake's `nixpkgs` directly

### 1.2 The asymmetry

`up` has `inputs.nixpkgs.follows = "nixpkgs"` so when `nix flake update` runs:
- `nixpkgs` (stable) gets a new rev → Up rebuilds with fresh stable packages

`vexboard` has NO `follows`, so when `nix flake update` runs:
- The outer `nixpkgs-unstable` (stable outer input) gets a new rev
- BUT `nixpkgs_3` (vexboard's private node) also gets updated to the latest nixos-unstable
- These are TWO SEPARATE nixos-unstable nodes, both pinned independently

This means:
1. An extra nixpkgs node in the lock graph (evaluation overhead)
2. Vexboard builds against its own nixpkgs-unstable pin rather than the outer flake's shared one

### 1.3 Why `nixpkgs-unstable` is the correct target (not `nixpkgs`)

The existing comment says "Do NOT add follows = 'nixpkgs'" because vexboard needs nixos-unstable
for its Rust/WASM toolchain. Adding `follows = "nixpkgs-unstable"` is SAFE and CORRECT:
- vexboard already targets nixos-unstable internally
- The outer flake's `nixpkgs-unstable` is also nixos-unstable
- rust-overlay works with any recent nixpkgs; there is no strict rev coupling

---

## 2) Problem definition

The user wants vexboard to "update daily like Up does" — meaning when `nix flake update`
runs (via `just update` or the Up GUI), vexboard should build against the same
nixpkgs-unstable revision as the outer flake, rather than maintaining an independent pin.

Currently vexboard has its own pinned `nixpkgs_3` node. After this change, vexboard will
use the outer flake's `nixpkgs-unstable` node — the same deduplication pattern `up` uses
with `nixpkgs`.

---

## 3) Proposed solution

Add `inputs.nixpkgs.follows = "nixpkgs-unstable"` to the `vexboard` input in `flake.nix`.

Change from:
```nix
# Do NOT add inputs.vexboard.inputs.nixpkgs.follows = "nixpkgs" — vexboard builds
# against nixos-unstable with rust-overlay; forcing stable nixpkgs breaks the
# Rust/WASM toolchain.
vexboard.url = "github:VictoryTek/vexboard";
```

Change to:
```nix
# vexboard: VexOS Server dashboard (Rust + WASM). Used by modules/server/vexboard.nix.
# Follows nixpkgs-unstable (not nixpkgs/stable) — vexboard builds against nixos-unstable
# with rust-overlay; following the outer nixpkgs-unstable keeps it in sync with the outer
# flake's unstable pin rather than maintaining its own independent nixpkgs_3 node.
# Do NOT change follows to "nixpkgs" (stable) — that breaks the Rust/WASM toolchain.
vexboard = {
  url = "github:VictoryTek/vexboard";
  inputs.nixpkgs.follows = "nixpkgs-unstable";
};
```

---

## 4) Implementation steps

1. Edit `flake.nix`: convert `vexboard.url = ...` (single-line form) to attrset form with
   `inputs.nixpkgs.follows = "nixpkgs-unstable"` and update the comment.
2. Run `nix flake update vexboard --impure` (or `nix flake update --impure`) to regenerate
   `flake.lock` with the merged nixpkgs-unstable node.
3. Validate with `nix flake show --impure`.
4. Run dry-build on core variants.

---

## 5) Risks and mitigations

| Risk | Likelihood | Mitigation |
|------|-----------|-----------|
| rust-overlay incompatibility with outer nixpkgs-unstable rev | Low | rust-overlay works with any recent nixpkgs; confirmed by dry-build |
| vexboard package fails to build with newer nixpkgs-unstable | Low | dry-build catches this before switch |
| Regressions in services.vexboard options | Very low | NixOS module is in the vexboard flake itself, not nixpkgs |

---

## 6) Files to modify

- `flake.nix` — convert `vexboard` input to attrset with `follows`
- `flake.lock` — regenerated automatically by `nix flake update`
