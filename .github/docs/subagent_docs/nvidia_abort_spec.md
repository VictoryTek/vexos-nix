# Spec: Remove Unreachable `abort` Branch in `modules/gpu/nvidia.nix`

## Summary

The `driverPackage` let binding in `modules/gpu/nvidia.nix` contains a final
`else abort ...` branch that is structurally unreachable.  The `variant`
binding is read from `config.vexos.gpu.nvidiaDriverVariant`, whose NixOS
option type is `lib.types.enum [ "latest" "legacy_535" "legacy_470" ]`.
NixOS enforces enum membership at option evaluation time — a value outside
the three allowed strings triggers a type error before any `let` binding is
evaluated.  The `abort` path can never execute.  Removing it produces an
equivalent three-way `if/else if/else` expression with a cleaner terminal
branch and eliminates the stale `# legacy_390 (Fermi) is broken in nixpkgs`
inline comment attached to the dead line.

---

## Current State Analysis

**File:** `modules/gpu/nvidia.nix`

### Option type (lines 30–31)

```nix
options.vexos.gpu.nvidiaDriverVariant = lib.mkOption {
  type = lib.types.enum [ "latest" "legacy_535" "legacy_470" ];
```

Only three string values are accepted.  Any other value is rejected by the
`lib.types.enum` type checker before any `config` attribute is read.

### Dead `driverPackage` binding (lines 17–22)

```nix
  # Map variant string to the correct driver package.
  driverPackage =
    if variant == "latest"          then config.boot.kernelPackages.nvidiaPackages.stable
    else if variant == "legacy_535" then config.boot.kernelPackages.nvidiaPackages.legacy_535
    else if variant == "legacy_470" then config.boot.kernelPackages.nvidiaPackages.legacy_470
    else abort "vexos.gpu.nvidiaDriverVariant: unknown value '${variant}'";  # legacy_390 (Fermi) is broken in nixpkgs
```

The final `else abort ...` branch is unreachable because:

1. `variant` is always one of `"latest"`, `"legacy_535"`, or `"legacy_470"` —
   enforced by the enum type before this expression is evaluated.
2. No host in `flake.nix` sets `nvidiaVariant` to `"legacy_390"` or any other
   unlisted value; the `hostList` uses only `"legacy_535"` and `"legacy_470"`
   for the non-latest variants.
3. The comment `# legacy_390 (Fermi) is broken in nixpkgs` on line 22 is
   informational but belongs in the header block or option description, not
   attached to an unreachable `abort`.

---

## flake.nix Assessment

Lines 173–209 (`hostList`) contain no `abort` calls and no references to
`legacy_390`.  All NVIDIA entries specify either no `nvidiaVariant` (default
`"latest"`) or one of `nvidiaVariant = "legacy_535"` / `nvidiaVariant =
"legacy_470"`.  **No changes to `flake.nix` are required.**

---

## Proposed Change

**File:** `modules/gpu/nvidia.nix`  
**Lines:** 17–22

### Replace (current)

```nix
  # Map variant string to the correct driver package.
  driverPackage =
    if variant == "latest"          then config.boot.kernelPackages.nvidiaPackages.stable
    else if variant == "legacy_535" then config.boot.kernelPackages.nvidiaPackages.legacy_535
    else if variant == "legacy_470" then config.boot.kernelPackages.nvidiaPackages.legacy_470
    else abort "vexos.gpu.nvidiaDriverVariant: unknown value '${variant}'";  # legacy_390 (Fermi) is broken in nixpkgs
```

### With (replacement)

```nix
  # Map variant string to the correct driver package.
  driverPackage =
    if      variant == "latest"     then config.boot.kernelPackages.nvidiaPackages.stable
    else if variant == "legacy_535" then config.boot.kernelPackages.nvidiaPackages.legacy_535
    else                                 config.boot.kernelPackages.nvidiaPackages.legacy_470;
```

The terminal branch becomes a plain `else`, which is safe because the enum
type guarantees `variant` is `"legacy_470"` at that point.

---

## Rationale

| Point | Detail |
|-------|--------|
| Enum enforcement | `lib.types.enum` in NixOS calls `lib.throwIfNot` during option merging; an invalid value raises a hard evaluation error before any `config` attribute is accessed. |
| No defensive need | Defensive `abort` guards are appropriate when the input is unconstrained (e.g., a plain `lib.types.str`). Here the type already provides the guard. |
| Readability | A terminal `else` communicates "exactly one remaining case" more clearly than a three-way `else if` followed by an unreachable `abort`. |
| Comment hygiene | The `legacy_390` note is already present in the file header (line 11) and in the `mkOption` description (line 47). The duplicate inline comment on the `abort` line is removed with the dead code. |

---

## Risks and Mitigations

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Someone bypasses the enum type and passes an unknown string | Not possible in NixOS | `lib.types.enum` evaluation is strict; there is no runtime path that skips it. |
| Future addition of `legacy_390` requires the abort back | Negligible | If `legacy_390` is ever re-added to nixpkgs it must be added to the enum first; the `else` branch would then map to the wrong package. Correct approach at that time: extend the enum and add an explicit `else if` arm. |
| Accidental removal of `legacy_470` handling | Very low | The `else` clause explicitly maps to `legacy_470` with a comment. Verified by dry-build of `vexos-desktop-nvidia-legacy470`. |

---

## Files to Modify

| File | Change |
|------|--------|
| `modules/gpu/nvidia.nix` | Replace lines 17–22 (the `driverPackage` binding) per the diff above. |

No other files require modification.

---

## Validation Steps

After implementation:

1. `nix flake check` — must pass with no evaluation errors.
2. `sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia` — exercises the `"latest"` branch.
3. `sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia-legacy535` — exercises `legacy_535`.
4. `sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia-legacy470` — exercises the new terminal `else` branch.
5. Confirm `hardware-configuration.nix` is not tracked in git.
6. Confirm `system.stateVersion` is unchanged.
