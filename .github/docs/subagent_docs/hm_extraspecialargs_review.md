# Review: home-manager extraSpecialArgs Fix

**Feature:** `hm_extraspecialargs`
**Reviewer:** Code Review Agent
**Date:** 2026-04-10
**Spec:** `.github/docs/subagent_docs/hm_extraspecialargs_spec.md`

---

## Fix Verification Results

### 1. `nixosModules.base` — `extraSpecialArgs` present?

**PASS.** The `home-manager` block inside `nixosModules.base` now reads:

```nix
home-manager = {
  useGlobalPkgs    = true;
  useUserPackages  = true;
  extraSpecialArgs = { inherit inputs; };
  users.nimda      = import ./home.nix;
};
```

`extraSpecialArgs = { inherit inputs; };` is present alongside all three sibling options.

---

### 2. `nixosModules.statelessBase` — `extraSpecialArgs` present?

**PASS.** The `home-manager` block inside `nixosModules.statelessBase` now reads:

```nix
home-manager = {
  useGlobalPkgs    = true;
  useUserPackages  = true;
  extraSpecialArgs = { inherit inputs; };
  users.nimda      = import ./home.nix;
};
```

`extraSpecialArgs = { inherit inputs; };` is present alongside all three sibling options.

---

### 3. `homeManagerModule` let-binding — unchanged?

**PASS.** The `homeManagerModule` block remains:

```nix
homeManagerModule = {
  imports = [ home-manager.nixosModules.home-manager ];
  home-manager = {
    useGlobalPkgs    = true;
    useUserPackages  = true;
    extraSpecialArgs = { inherit inputs; };
    users.nimda      = import ./home.nix;
    backupFileExtension = "backup";
  };
};
```

No modifications to this block.

---

### 4. Scope of changes — no unintended modifications?

**PASS.** The diff is contained to exactly two line additions:
- `extraSpecialArgs = { inherit inputs; };` in `nixosModules.base`
- `extraSpecialArgs = { inherit inputs; };` in `nixosModules.statelessBase`

No other blocks, attributes, or files were altered.

---

## Correctness Check

### 5. `home.nix` formal parameter declaration

**PASS.** `home.nix` line 5:

```nix
{ config, pkgs, lib, inputs, ... }:
```

`inputs` is an explicitly named formal parameter. The fix is required and sufficient to satisfy this declaration.

---

### 6. Attribute path correctness

**PASS.** The official home-manager NixOS module attribute for passing extra arguments to home modules is `home-manager.extraSpecialArgs`. This is the exact path used in the fix. Per home-manager documentation, this option creates an additional set of arguments passed to every home-manager module alongside `config`, `pkgs`, and `lib`.

---

### 7. `inherit inputs;` — syntactically correct and in scope?

**PASS.** `inputs` is the `@inputs` binding from the `outputs` function signature:

```nix
outputs = { self, nixpkgs, nixpkgs-unstable, nix-gaming, home-manager, impermanence, ... }@inputs:
```

`nixosModules` is defined inside the `in { ... }` block of this function. The lambda captures `inputs` via lexical closure, making `inherit inputs;` valid in both `base` and `statelessBase`.

---

## Nix Syntax Check

### 8–10. Syntax, semicolons, braces

**PASS.**

- All attribute assignments in the modified blocks end with `;`
- `extraSpecialArgs = { inherit inputs; };` — the inner set `{ inherit inputs; }` is properly braced, and the outer assignment ends with `;`
- Surrounding attribute sets are fully balanced
- No orphan or doubled braces detected

---

## Scope Check

### 11. `inputs` in scope at definition sites?

**PASS.** Both `nixosModules.base` and `nixosModules.statelessBase` are evaluated inside the `outputs` function body, which receives `inputs` as a named binding. Lexical scoping in Nix means `inputs` is accessible throughout the entire `in { ... }` block without any additional plumbing.

---

## Minor Observations (Non-Blocking)

| Observation | Severity | Introduced by fix? |
|-------------|----------|--------------------|
| `backupFileExtension = "backup";` present in `homeManagerModule` but absent from `nixosModules.base` and `nixosModules.statelessBase` | Minor — pre-existing inconsistency | No — pre-existing |
| `nixosModules.statelessBase` retains `_module.args.inputs = inputs;` alongside the new `extraSpecialArgs` | Acceptable — the `_module.args` injection covers NixOS modules; `extraSpecialArgs` covers home-manager modules. Both are needed when downstream NixOS modules also reference `inputs` | No — pre-existing design |

Neither observation is a defect introduced by this fix.

---

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 100% | A |
| Code Quality | 98% | A |
| Security | 100% | A |
| Consistency | 95% | A |
| Build Success | N/A | UNTESTED |

**Overall Grade: A (99%)**

*Note: Consistency deducted 5% for the pre-existing `backupFileExtension` gap between `homeManagerModule` and the `nixosModules` exports, which is unrelated to this fix but is a latent inconsistency.*

---

## Verdict

**PASS**

The fix is correct, complete, and scoped exactly as specified. Both `nixosModules.base` and `nixosModules.statelessBase` now include `home-manager.extraSpecialArgs = { inherit inputs; };`, which will cause home-manager to supply `inputs` to `home.nix` when these modules are consumed via the `/etc/nixos/flake.nix` template. No unintended changes were made. Syntax is valid. Scoping is correct.
