# Review: `roles` Table Refactor (`commonBase` / `proxmoxBase` extraction)

**Feature:** `roles_table_refactor`
**Spec:** `.github/docs/subagent_docs/roles_table_refactor_spec.md`
**Files reviewed:** `flake.nix`
**Review date:** 2026-05-15

---

## 1. Spec Compliance

### 1.1 New `let` bindings

| Binding | Expected | Actual | Match? |
|---|---|---|---|
| `commonBase` | `[ unstableOverlayModule customPkgsOverlayModule ]` | `[ unstableOverlayModule customPkgsOverlayModule ]` | ✓ |
| `proxmoxBase` | `[ proxmoxOverlayModule inputs.proxmox-nixos.nixosModules.proxmox-ve ]` | `[ proxmoxOverlayModule inputs.proxmox-nixos.nixosModules.proxmox-ve ]` | ✓ |
| Placement | Immediately before the `roles` comment block | Immediately after `serverServicesModule`, before `# Single source of truth…` | ✓ |

### 1.2 `roles` table — `baseModules` field

| Role | Spec | Actual | Match? |
|---|---|---|---|
| `desktop` | `commonBase ++ [ upModule ]` | `commonBase ++ [ upModule ]` | ✓ |
| `htpc` | `commonBase ++ [ upModule ]` | `commonBase ++ [ upModule ]` | ✓ |
| `stateless` | `commonBase ++ [ upModule ]` | `commonBase ++ [ upModule ]` | ✓ |
| `server` | `commonBase ++ [ upModule ] ++ proxmoxBase` | `commonBase ++ [ upModule ] ++ proxmoxBase` | ✓ |
| `headless-server` | `commonBase ++ proxmoxBase` | `commonBase ++ proxmoxBase` | ✓ |
| `vanilla` | `[]` | `[]` | ✓ |

### 1.3 `extraModules` field (must be unchanged)

| Role | Before | After | Match? |
|---|---|---|---|
| `desktop` | `[]` | `[]` | ✓ |
| `htpc` | `[]` | `[]` | ✓ |
| `stateless` | `[ impermanence.nixosModules.impermanence ]` | `[ impermanence.nixosModules.impermanence ]` | ✓ |
| `server` | `serverServicesModule` | `serverServicesModule` | ✓ |
| `headless-server` | `serverServicesModule` | `serverServicesModule` | ✓ |
| `vanilla` | `[]` | `[]` | ✓ |

### 1.4 `homeFile` field (must be unchanged)

All six `homeFile` values are identical before and after the refactor — confirmed by diff. ✓

---

## 2. Semantic Correctness

The refactor changes the order of modules within `baseModules` for five roles.
As documented in the spec (Section 3.3 and Section 4), this is safe because:

- `nixpkgs.overlays` is a **merged list** (concatenated), not overridden.
- The three overlay modules (`unstableOverlayModule`, `customPkgsOverlayModule`,
  `proxmoxOverlayModule`) operate on independent namespaces (`pkgs.unstable`,
  `pkgs.vexos`, `pkgs.proxmox-ve`) and do not reference each other.
- `upModule` appends to `environment.systemPackages` only — no conflict risk.
- `inputs.proxmox-nixos.nixosModules.proxmox-ve` sets `services.*` options that
  have no interaction with the overlay modules.

**Flattened module list comparison:**

| Role | Before (flattened) | After (flattened) | Semantically equivalent? |
|---|---|---|---|
| `desktop` | `[unstableOverlayModule, upModule, customPkgsOverlayModule]` | `[unstableOverlayModule, customPkgsOverlayModule, upModule]` | ✓ Yes |
| `htpc` | `[unstableOverlayModule, upModule, customPkgsOverlayModule]` | `[unstableOverlayModule, customPkgsOverlayModule, upModule]` | ✓ Yes |
| `stateless` | `[unstableOverlayModule, upModule, customPkgsOverlayModule]` | `[unstableOverlayModule, customPkgsOverlayModule, upModule]` | ✓ Yes |
| `server` | `[unstableOverlayModule, upModule, proxmoxOverlayModule, customPkgsOverlayModule, proxmox-ve]` | `[unstableOverlayModule, customPkgsOverlayModule, upModule, proxmoxOverlayModule, proxmox-ve]` | ✓ Yes |
| `headless-server` | `[unstableOverlayModule, proxmoxOverlayModule, customPkgsOverlayModule, proxmox-ve]` | `[unstableOverlayModule, customPkgsOverlayModule, proxmoxOverlayModule, proxmox-ve]` | ✓ Yes |
| `vanilla` | `[]` | `[]` | ✓ Yes |

**Key invariants preserved:**
- `headless-server` has NO `upModule` — confirmed. ✓
- `vanilla` has NO `commonBase` — `baseModules = []` unchanged. ✓
- `server` HAS `upModule` (display-capable) — confirmed. ✓

---

## 3. Scope of Changes (No Unintended Modifications)

Git diff analysis of `flake.nix`:

```
+6 lines added   — 2 new let bindings + 4 updated comment lines in server/headless-server
-8 lines removed — old verbose baseModules lists + superseded comment lines
```

**Confirmed unchanged:**
- All inputs (no new flake inputs added)
- `serverServicesModule` binding
- `mkHomeManagerModule` function
- `mkHost` function
- `hostList` table (34 entries)
- `mkBaseModule` function (reads `proxmoxOverlayModule` directly, not via `proxmoxBase` — correct, intentional)
- All outputs (`nixosConfigurations`, `nixosModules`, `packages`, `devShells`)
- No other files modified

The diff is exactly and only what the spec prescribes. ✓

---

## 4. Code Quality Observations

- Comments in `server` and `headless-server` were updated to reflect `proxmoxBase`
  usage while preserving the critical "avoid infinite recursion" rationale. The new
  comment is cleaner and cross-references the server entry from headless-server — a
  minor improvement over the original.
- New bindings use consistent 4-space indentation matching the surrounding `let` block.
- Naming (`commonBase`, `proxmoxBase`) is clear and self-documenting.
- `commonBase` correctly excludes `upModule` (role-specific) — clean separation of concerns.

---

## 5. Build Validation

| Command | Result |
|---|---|
| `nix flake check --impure` | ✓ PASSED (exit 0) |
| `nix build --dry-run --impure .#nixosConfigurations.vexos-desktop-amd.config.system.build.toplevel` | ✓ PASSED |
| `nix build --dry-run --impure .#nixosConfigurations.vexos-headless-server-amd.config.system.build.toplevel` | ✓ PASSED |

All 34 flake outputs evaluate successfully (`nix flake check`).
Both targeted closures resolve without error.

---

## 6. Score Table

| Category | Score | Grade |
|---|---|---|
| Specification Compliance | 100% | A+ |
| Best Practices | 100% | A+ |
| Functionality | 100% | A+ |
| Code Quality | 100% | A+ |
| Security | 100% | A+ |
| Performance | 100% | A+ |
| Consistency | 100% | A+ |
| Build Success | 100% | A+ |

**Overall Grade: A+ (100%)**

---

## 7. Summary

The implementation is a **clean, exact match** of the specification with zero deviations.

- Both `commonBase` and `proxmoxBase` let-bindings are correctly placed and correctly
  composed.
- All six role `baseModules` entries use the new bindings as specified; no entry was
  missed or incorrectly modified.
- `extraModules` and `homeFile` are untouched across all roles.
- `vanilla.baseModules = []` is preserved — `commonBase` is correctly NOT applied.
- `headless-server` correctly has no `upModule`.
- The module list order change is semantically equivalent (non-conflicting, independent
  namespaces — confirmed by spec analysis and build validation).
- `mkBaseModule` is unaffected (it does not consume `roles.baseModules`).
- No files other than `flake.nix` were modified.
- All build and flake checks pass.

**Result: PASS**
