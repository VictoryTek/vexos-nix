# Review: NVIDIA Legacy Driver Support — Phase 2 (Flake Outputs)
**Feature Name:** `nvidia_legacy_drivers`
**Review File:** `.github/docs/subagent_docs/nvidia_legacy_drivers_review.md`
**Date:** 2026-04-14
**Reviewer:** QA Subagent (Phase 3)
**Spec:** `.github/docs/subagent_docs/nvidia_legacy_drivers_spec.md`
**Reviewed Files:** `flake.nix`, `modules/gpu/nvidia.nix`, `README.md`, `template/etc-nixos-flake.nix`
**Phase:** 2 — Flake outputs (supersedes Phase 1 module review dated 2026-04-02)

---

## Score Table

| Category | Score | Grade |
|---|---|---|
| Specification Compliance | 65% | C |
| Best Practices | 80% | B |
| Functionality | 85% | B+ |
| Code Quality | 85% | B+ |
| Security | 100% | A+ |
| Performance | 100% | A+ |
| Consistency | 75% | C+ |
| Build Success | 50% | D |

**Overall Grade: C+ (80%)**

---

## Build Result

`nix flake check --impure` was executed in `/home/nimda/Projects/vexos-nix`.

**Exit code: 1**

```
error: Failed assertions:
- You must set the option 'boot.loader.grub.devices' or 'boot.loader.grub.mirroredBoots'
  to make the system bootable.
```

This failure occurs on **all** outputs — including the pre-existing `vexos-desktop-amd` —
because `/etc/nixos/hardware-configuration.nix` does not exist on this development machine.
The error is an infrastructure constraint of the build environment, **not** introduced by this
implementation. The `nix flake check` fallback in `scripts/preflight.sh` explicitly skips the
check when hardware-configuration.nix is absent.

**Assessment basis:** Static inspection of all modified and adjacent files combined with
the partial build output above. The new outputs were not the immediate failure cause.

Build category is scored at 50% (cannot confirm full pass or clean failure isolation).

---

## 1. Specification Compliance — 65% C

### 1.1 Required Flake Outputs — PRESENT ✓

All 6 outputs required by the review prompt checklist are present in `flake.nix`:

| Flake output | Variant injected | Modules base | Status |
|---|---|---|---|
| `vexos-desktop-nvidia-legacy470` | `legacy_470` | `commonModules` | ✓ |
| `vexos-desktop-nvidia-legacy390` | `legacy_390` | `commonModules` | ✓ |
| `vexos-htpc-nvidia-legacy470` | `legacy_470` | `minimalModules` | ✓ |
| `vexos-htpc-nvidia-legacy390` | `legacy_390` | `minimalModules` | ✓ |
| `vexos-stateless-nvidia-legacy470` | `legacy_470` + impermanence | `commonModules` | ✓ |
| `vexos-stateless-nvidia-legacy390` | `legacy_390` + impermanence | `commonModules` | ✓ |

Each injects the variant as an inline single-attribute module (`{ vexos.gpu.nvidiaDriverVariant = ...; }`),
exactly as specified in spec Section 4.1 and Section 5 Step 2.

### 1.2 Existing Output Unaffected — PASS ✓

`vexos-desktop-nvidia` continues to use only `commonModules ++ [ ./hosts/desktop-nvidia.nix ]`
with no variant override, so `vexos.gpu.nvidiaDriverVariant` defaults to `"latest"`. ✓

### 1.3 CRITICAL MISS — `modules/gpu/nvidia.nix` documentation not updated

Spec Step 1 required two documentation corrections to `modules/gpu/nvidia.nix`.
Neither was applied.

**File header comment — NOT updated:**

Current (wrong):
```nix
#   "latest"     — Turing (RTX 20xx / GTX 16xx) and newer  [default]
#   "legacy_535" — Maxwell / Pascal / Volta (GTX 750–1080 Ti, Titan V)
```

Required per spec (not present):
```nix
#   "latest"     — Stable (570.x+) branch; open kernel modules; supports Maxwell (GTX 750+)
#                  through Ada/Hopper. Correct choice for GTX 750+, RTX 20/30/40xx and newer.
#   "legacy_535" — 535.x LTS branch; proprietary modules; open = false.
#                  Optional LTS alternative for Maxwell/Pascal/Volta. NOT architecturally required.
```

**Option description for `"legacy_535"` — NOT corrected:**

Current (wrong — implies "required"):
```
"legacy_535" — 535.x LTS branch; proprietary modules required.
               Use for Maxwell (GTX 750/Ti), Pascal (GTX 1050–1080 Ti), and Volta (Titan V).
```

Required per spec:
```
"legacy_535" — 535.x LTS branch; proprietary modules; open = false.
               Optional stable alternative for Maxwell (GTX 750+), Pascal (GTX 1050–1080 Ti),
               and Volta (Titan V) who prefer a proven LTS driver over current production.
               These GPUs work equally well with "latest"; this variant is NOT required.
```

**Impact:** A user with a GTX 1080 (Pascal) reads the current description and may incorrectly
believe they must use `legacy_535`. This is concrete misinformation introduced by the spec's
original wording that was explicitly scheduled for correction. Classification: **CRITICAL**.

### 1.4 CRITICAL MISS — `template/etc-nixos-flake.nix` not updated

Spec Step 3 required replacing the single NVIDIA rebuild comment in the template header with an
expanded block documenting all legacy variants. This was **not done**.

Current at template line 15:
```
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-desktop-nvidia
```

Required per spec:
```
#      NVIDIA GPU (desktop role):
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-desktop-nvidia              (RTX 20xx / GTX 16xx and newer)
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-desktop-nvidia-legacy535    (Maxwell/Pascal/Volta — LTS alt.)
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-desktop-nvidia-legacy470    (Kepler — GTX 600/700)
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-desktop-nvidia-legacy390    (Fermi  — GTX 400/500)
```

**Impact:** The primary user-facing installation template still presents only one NVIDIA option.
Users with legacy hardware following the template docs have no discovery path to the correct target.
Classification: **CRITICAL**.

### 1.5 MEDIUM — `legacy_535` inconsistency

The spec (Section 5 Step 2, note) requires the implementation subagent to:
- If `legacy_535` is available in nixos-25.11: add `vexos-desktop-nvidia-legacy535`,
  `vexos-htpc-nvidia-legacy535`, and `vexos-stateless-nvidia-legacy535` outputs.
- If `legacy_535` is NOT available: remove `"legacy_535"` from the enum in `modules/gpu/nvidia.nix`.

The implementation did **neither**: no `legacy_535` outputs were added, but `"legacy_535"` remains
in the enum. The current flake uses `nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11"`, and
`legacy_535` is known to exist in that branch. The module's `"legacy_535"` enum value is therefore
valid, but the corresponding flake outputs are absent. Classification: **MEDIUM** (enumerable
inconsistency; users who set the option manually can still use it, but no discoverable flake
output exists).

---

## 2. Forbidden Changes — PASS ✓

| Check | Result |
|---|---|
| `hardware-configuration.nix` NOT tracked in git | ✓ (`git ls-files` returned empty) |
| `system.stateVersion` unchanged | ✓ (`"25.11"` at configuration.nix line 123) |
| No new flake inputs added | ✓ (inputs block unchanged) |
| No host files modified | ✓ (`hosts/desktop-nvidia.nix`, `hosts/htpc-nvidia.nix`, `hosts/stateless-nvidia.nix` untouched) |

---

## 3. Code Quality — 85% B+

All 6 new `nixosConfigurations` entries follow the exact same structural pattern as existing outputs:

```nix
# ── <description> ──────────
# sudo nixos-rebuild switch --flake .#<output>
nixosConfigurations.<output> = nixpkgs.lib.nixosSystem {
  inherit system;
  modules = <base> ++ [
    ./hosts/<host>.nix
    { vexos.gpu.nvidiaDriverVariant = "<variant>"; }
  ];
  specialArgs = { inherit inputs; };
};
```

The HTPC outputs correctly use `minimalModules` (no home-manager), matching the other HTPC outputs.
The stateless outputs correctly include `impermanence.nixosModules.impermanence`, matching the
other stateless outputs. Header comments are accurate and include the rebuild command.

No dead code, no unnecessary abstraction. The inline module override is idiomatic NixOS practice
for per-output single-attribute overrides. No code duplication that a helper function could avoid
(a `mkNvidiaLegacy` helper would save ~5 lines per output but would reduce readability for
marginal gain; the current verbosity is appropriate).

Minor: the `vexos-desktop-nvidia-legacy535` output should either be present or commented out with
an explanation — its absence without any note is silent.

---

## 4. README Accuracy — PASS ✓

`README.md` was updated correctly:

- All 6 new outputs appear in the correct role tables (Desktop, Stateless, HTPC) with accurate
  descriptions.
- The Notes rebuild-commands block lists all new legacy targets by role.
- The existing variant descriptions were not inadvertently altered.

---

## 5. Security — 100% A+

No security concerns. Hardware driver configuration only. No secrets, network access, or
privilege escalation paths introduced.

---

## 6. Performance — 100% A+

New outputs share the same evaluated module tree as their base variants, differing only in one
attribute override. Closure evaluation overhead is negligible.

---

## 7. Consistency — 75% C+

Structural consistency of the new `flake.nix` outputs is excellent. However:

- The module option description misrepresents `"legacy_535"` as required for Maxwell/Pascal/Volta,
  which contradicts the spec's intended correction and is inconsistent with the `"latest"` driver
  behaviour documented elsewhere.
- The template (`template/etc-nixos-flake.nix`) is inconsistent with `flake.nix`: the flake
  exposes 6 new legacy outputs but the template user documentation doesn't mention any of them.

---

## Issues Summary

### CRITICAL Issues (block approval)

| # | File | Issue |
|---|---|---|
| C1 | `modules/gpu/nvidia.nix` | File header comment for `"legacy_535"` not updated — still implies Maxwell/Pascal/Volta require this branch |
| C2 | `modules/gpu/nvidia.nix` | Option `description` for `"legacy_535"` not corrected — still says "Use for Maxwell (GTX 750/Ti), Pascal, Volta"; does not say "NOT required" |
| C3 | `template/etc-nixos-flake.nix` | Spec Step 3 entirely absent — template still shows only `vexos-desktop-nvidia`; legacy variants not documented |

### MEDIUM Issues

| # | File | Issue |
|---|---|---|
| M1 | `flake.nix` | `legacy_535` outputs absent but enum value retained in `modules/gpu/nvidia.nix` — spec required one or the other to be resolved |

### LOW Issues

| # | File | Issue |
|---|---|---|
| L1 | `modules/gpu/nvidia.nix` | `"latest"` description does not explicitly mention Maxwell/Pascal/Volta compatibility; spec said to add this for discoverability |

---

## Final Verdict

**NEEDS_REFINEMENT**

The core functional deliverable (6 new flake outputs for legacy NVIDIA variants) is correctly
implemented and follows the NixOS module override pattern exactly as specified. README is well-updated.
However, three tasks defined in the spec are entirely absent:

1. `modules/gpu/nvidia.nix` header comment and option description corrections (spec Step 1)
2. `template/etc-nixos-flake.nix` documentation update (spec Step 3)
3. `legacy_535` enum/output consistency resolution (spec Note in Step 2)

CRITICAL issues C1, C2, and C3 must be resolved before this work can be approved. The
misinformation in the `"legacy_535"` description is particularly important because it may cause
users with Maxwell/Pascal/Volta hardware to choose a sub-optimal driver branch.

