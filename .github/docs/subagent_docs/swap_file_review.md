# Review: Swap File Implementation
**Feature:** `swap_file`  
**Date:** 2026-04-08  
**Reviewer:** Review & Quality Assurance Subagent  
**Files Reviewed:**
- `modules/swap.nix` (new module)
- `configuration.nix` (modified imports)
- `hosts/vm.nix` (VM host override)

---

## 1. Best Practices

### 1.1 `vexos.*` Option Pattern
**PASS** — `swap.nix` declares `options.vexos.swap.enable` using `lib.mkOption` with
`type = lib.types.bool` and `default = true`. This exactly mirrors the `vexos.btrfs.enable`
pattern in `modules/system.nix`. The namespace is correctly scoped under `vexos.swap`.

### 1.2 `lib.mkOption` Usage
**PASS** — `lib.mkOption` is used correctly with a `type`, `default`, and multi-line
`description` string. `lib.mkEnableOption` is an acceptable alternative but the spec
does not prescribe one over the other; `lib.mkOption` with explicit type is more explicit
and consistent with existing module style.

### 1.3 `lib.mkIf` Gating
**PASS** — The entire `config` block is wrapped in `lib.mkIf cfg.enable { ... }`, ensuring
no `swapDevices` are added to the system when the option is disabled (e.g. VM guest).

### 1.4 Swap Device Path and Size
**PASS** — `device = "/var/lib/swapfile"` and `size = 8192` (8 GiB expressed in MiB as
required by the NixOS `swapDevices.*.size` option). Both values match the spec exactly.

### 1.5 `randomEncryption` Handling
**PASS** — `randomEncryption` is intentionally omitted. Two inline comments explain the
reasoning:
1. Breaks hibernate (saved image is unreadable on resume with a random key)
2. Provides no benefit on LUKS-encrypted drives (double encryption overhead, no gain)

This aligns with spec Source 7 and the risk mitigation documented in the spec.

---

## 2. Consistency

### 2.1 Module Style vs. `modules/system.nix`
**PASS** — Style is near-identical:

| Element | `system.nix` | `swap.nix` |
|---|---|---|
| Function signature | `{ pkgs, lib, config, ... }:` | `{ lib, config, ... }:` |
| `let` binding | `cfg = config.vexos.btrfs` | `cfg = config.vexos.swap` |
| Option declaration | `lib.mkOption { type = lib.types.bool; default = true; ... }` | Same |
| Config gating | `config = lib.mkIf cfg.enable { ... }` | Same |

The only difference is `pkgs` is omitted from the function signature in `swap.nix` since no
packages are referenced — this is correct and intentional.

### 2.2 Import Placement in `configuration.nix`
**PASS** — `./modules/swap.nix` is the last entry in the imports list, placed after
`./modules/system.nix`. The ordering is alphabetically and logically consistent with the
existing import block. No existing imports were displaced or reordered.

### 2.3 `hosts/vm.nix` Override Style
**PASS** — `vexos.swap.enable = false;` in `hosts/vm.nix` is positioned immediately after
`vexos.btrfs.enable = false;`, with a parallel inline comment explaining the rationale
("VMs rely on hypervisor memory management — no disk swap file needed."). This mirrors
the exact style of the btrfs override.

---

## 3. Maintainability

### 3.1 Header Comment
**PASS** — The module header clearly explains:
- What the module does (persistent 8 GiB swap file)
- How it relates to ZRAM (complementary, not competitive)
- How `vm.swappiness = 10` influences usage priority

### 3.2 Btrfs/Snapper Warning
**PASS** — A detailed btrfs warning is present in the header comment. It explains:
- The `snapper` snapshot incompatibility with an active swapfile in the same subvolume
- The recommended mitigation (dedicated `/swap` btrfs subvolume in `hardware-configuration.nix`)
- That nixpkgs handles `NODATACOW` automatically via `btrfs filesystem mkswapfile`

This is actionable and accurate per spec Sources 3–5.

### 3.3 Inline Comments
**PASS** — `size = 8192; # 8 GiB in MiB` provides clear unit documentation. The
`randomEncryption` omission comment block explains both reasons concisely.

---

## 4. Completeness

### 4.1 `modules/swap.nix`
**PASS** — Module implements:
- `options.vexos.swap.enable` option (bool, default true)
- `config = lib.mkIf cfg.enable { swapDevices = [...]; }` block
- All required fields: `device`, `size`
- `randomEncryption` explicitly excluded with documentation

### 4.2 `configuration.nix` — Import Present
**PASS** — `./modules/swap.nix` is confirmed present as the last line of the `imports`
list in `configuration.nix`.

### 4.3 `hosts/vm.nix` — Override Present
**PASS** — `vexos.swap.enable = false;` is confirmed present in `hosts/vm.nix` with an
appropriate explanatory comment.

---

## 5. Security

### 5.1 `randomEncryption` Absence
**PASS** — `randomEncryption` is not enabled. This is the correct decision given:
- Bare-metal hosts likely use LUKS full-disk encryption (making swap-level encryption
  redundant)
- Hibernate support would break if random swap encryption were enabled
- Spec explicitly documents this rationale

### 5.2 No Hardcoded Secrets
**PASS** — No passwords, tokens, keys, UUIDs, or other sensitive data appear in any of
the three modified files.

### 5.3 No World-Writable Paths or Privilege Escalation
**PASS** — The swap file path `/var/lib/swapfile` is a standard system path. NixOS's
built-in `mkswap` systemd service creates it with correct ownership and permissions (root
600).

---

## 6. Build Validation

### Environment
**NOTE:** The current execution environment is **Windows (PowerShell)**. The `nix` CLI
is not installed on this host, which is the expected state for a Windows development
workstation. All NixOS build commands require a Linux environment with Nix installed.

**Command attempted:**
```
nix flake check
```
**Result:**
```
CommandNotFoundException: The term 'nix' is not recognized
```

**Classification:** NOT A FAILURE — `nix` unavailability on Windows is an environmental
constraint, not a code defect. The instructions specify: "do not block on these if nix is
not available — note unavailability."

### Static Analysis (Nix Syntax & Semantics)
In lieu of live build execution, a full static analysis was performed:

| Check | Result |
|---|---|
| `swap.nix` Nix syntax | Valid — proper attribute set structure, string literals, integer literals |
| `swapDevices` option type | Correct — list of attribute sets, matching `nixos/modules/config/swap.nix` |
| `size = 8192` type | Correct — integer, interpreted as MiB by NixOS (matches `null or int`) |
| `device = "/var/lib/swapfile"` | Correct — nonEmptyStr, valid absolute path |
| `lib.mkOption` / `lib.mkIf` usage | Correct — identical structure to `system.nix` which is known-working |
| `configuration.nix` import | Correct — path `./modules/swap.nix` resolves to the new file |
| `hosts/vm.nix` option reference | Correct — `vexos.swap.enable` is declared in `swap.nix` which is imported through `configuration.nix` |
| No new flake inputs introduced | Correct — `swap.nix` uses only `lib` and `config`, no external dependencies |
| No `nixpkgs.follows` issues | N/A — no new inputs |

**Static Analysis Verdict:** No issues found. The implementation uses only built-in NixOS
options and standard `lib` functions.

### dry-build Commands
Not executed — `nix` CLI unavailable on Windows host. These must be run on a NixOS
or Linux system with Nix installed before deployment.

---

## 7. Safety Guards

### 7.1 `hardware-configuration.nix` Not in Repository
**PASS** — A repo-wide file search for `hardware-configuration.nix` returned **no results**.
The file is correctly kept outside the repository (lives at `/etc/nixos/` on the host).

### 7.2 `system.stateVersion` Unchanged
**PASS** — `system.stateVersion = "25.11"` is present in `configuration.nix`. None of the
three modified files touch `system.stateVersion`. The value has not been changed.

---

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 100% | A |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | N/A* | — |

**Overall Grade: A (100% — static analysis; live build pending Linux environment)**

*`nix` CLI unavailable on Windows host. Static analysis shows no issues. Live
`nix flake check` and `nixos-rebuild dry-build` must be confirmed on a Linux/NixOS system.

---

## Summary

All three files are correctly implemented and fully consistent with the specification and
existing module patterns:

- **`modules/swap.nix`**: Clean, minimal, idiomatic. Uses the exact `vexos.*` option
  pattern from `system.nix`. Correctly gates config with `lib.mkIf`. Correct path and
  size. `randomEncryption` correctly omitted with documentation. Btrfs warning present
  and accurate.
- **`configuration.nix`**: Import correctly appended as the last item in the imports list.
  No other changes made to the file.
- **`hosts/vm.nix`**: Override `vexos.swap.enable = false` present with explanatory
  comment, styled identically to the adjacent `vexos.btrfs.enable = false` line.

No issues were found in any category.

---

## Final Verdict

**PASS**

All static checks pass. Implementation is complete, correct, and consistent.
Live build validation (`nix flake check`, `nixos-rebuild dry-build`) must be executed on
a Linux/NixOS host before deployment — this is an environmental constraint of the review
machine, not a code issue.
