# Review: Fix `sed: command not found` — install_sed_fix

**Feature:** `install_sed_fix`
**Phase:** 3 — Review & Quality Assurance
**Date:** 2026-04-08
**Reviewer:** Review Subagent
**Spec:** `.github/docs/subagent_docs/install_sed_fix_spec.md`

---

## 1. Modified Files Reviewed

- `template/etc-nixos-flake.nix`
- `scripts/install.sh`

---

## 2. Checklist Results

### 2.1 Nix Fix — `template/etc-nixos-flake.nix`

| Check | Result | Notes |
|-------|--------|-------|
| `bootloaderModule` is function `{ pkgs, ... }: { ... }` | ✅ PASS | Confirmed at line 63 |
| `sed` replaced by `${pkgs.gnused}/bin/sed` | ✅ PASS | Confirmed at line 67 |
| Module is syntactically valid Nix | ✅ PASS | `nix eval` returned exit 0 |
| Rest of flake template untouched | ✅ PASS | No unrelated changes detected |
| `bootloaderModule` wired correctly into `nixosConfigurations` | ✅ PASS | Used via `mkVariant` → `modules = [...bootloaderModule...]` |
| No unrelated changes | ✅ PASS | Only the `bootloaderModule` declaration changed |

### 2.2 Shell Fix — `scripts/install.sh`

| Check | Result | Notes |
|-------|--------|-------|
| `export PATH=...` added immediately before `nixos-rebuild switch` | ✅ PASS | Present with `/run/current-system/sw/bin` and Nix paths prepended |
| `sudo systemctl set-environment PATH="$PATH"` called before `nixos-rebuild` | ✅ PASS | Present immediately after export |
| `sudo systemctl unset-environment PATH` called after `nixos-rebuild` (success path) | ✅ PASS | Present at end of script after the if/fi block |
| PATH string properly quoted | ✅ PASS | `"$PATH"` double-quoted throughout |
| No unrelated changes | ✅ PASS | Only PATH guard block and unset line added |
| Script is syntactically valid bash | ✅ PASS | `bash -n` returned exit 0 |

#### Minor Deviations from Spec (non-critical)

1. **`/run/wrappers/bin` absent from explicit PATH prefix** — The spec (Section 5.1) includes `/run/wrappers/bin` in the hardcoded PATH string. The implementation omits it from the prefix but appends `$PATH` at the end (`...:/bin:$PATH`). On all NixOS systems, `/run/wrappers/bin` is present in the shell's inherited PATH; appending `$PATH` preserves it. Risk: effectively zero.

2. **No `2>/dev/null || true` on `systemctl set-environment`** — The spec adds this guard to suppress errors if systemd is unavailable. The implementation omits it. Since `install.sh` uses `set -uo pipefail` (not `set -e`), a non-zero return code from `systemctl` will not abort the script. Risk: negligible.

3. **Comment block shorter than spec template** — The implementation uses a 2-line comment rather than the 9-line comment from spec Section 5.1. The intent is still clearly communicated. Risk: none.

---

## 3. Build Validation

### 3.1 Bash syntax check

```
bash -n scripts/install.sh
```
**Exit code: 0** — Script is syntactically valid.

### 3.2 Nix template evaluation

```
nix eval --file template/etc-nixos-flake.nix
```
**Exit code: 0**

Output:
```
{ inputs = { nixpkgs = { follows = "vexos-nix/nixpkgs"; }; vexos-nix = { url = "github:VictoryTek/vexos-nix"; }; };
  outputs = «lambda outputs @ template/etc-nixos-flake.nix:58:13»; }
```

The template evaluates cleanly as a valid Nix attrset. The `outputs` lambda is unevaluated (expected — it references `builtins.getFlake`-equivalent constructs that require a flake context). No parse errors.

### 3.3 `nix flake check --impure`

```
nix flake check --impure
```
**Exit code: 0**

Warnings only (all pre-existing, unrelated to this change):
- `warning: Git tree has uncommitted changes` — expected (working tree has the new changes not yet committed)
- `warning: Using 'builtins.derivation' ... options.json ... without a proper context` ×4 — pre-existing nixpkgs internals warning, not introduced by this change

Note: `nix flake check` (pure mode) fails with `error: access to absolute path '/etc/nixos/hardware-configuration.nix' is forbidden in pure evaluation mode`. This is a pre-existing, expected failure for this repository because `hosts/*.nix` imports `/etc/nixos/hardware-configuration.nix` which is host-generated and not tracked in the repo. Running with `--impure` is the documented workaround confirmed in the spec.

---

## 4. Security

| Check | Result |
|-------|--------|
| No secrets or credentials in modified files | ✅ PASS |
| PATH manipulation uses only well-known NixOS system paths | ✅ PASS |
| No paths removed from PATH (prepend-only strategy) | ✅ PASS |
| `systemctl set-environment` / `unset-environment` are standard systemd operations | ✅ PASS |
| Appending `$PATH` at end carries no injection risk (value from shell, not external input) | ✅ PASS |

---

## 5. Root Cause Verification

The primary defect (`bare sed in extraInstallCommands` → `command not found` in systemd-run unit) is fully resolved:

- `bootloaderModule` is now a module function that receives `pkgs` from the NixOS module system
- `${pkgs.gnused}/bin/sed` is evaluated at Nix evaluation time to an absolute store path (e.g., `/nix/store/xxx-gnused-x.y.z/bin/sed`)
- The generated `install-systemd-boot.sh` store artifact will contain the absolute path, making it immune to any PATH stripping by `systemd-run`

The secondary fix (PATH guard in `install.sh`) correctly covers users who have already downloaded the old template to `/etc/nixos/flake.nix` and re-run the installer.

---

## 6. Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 92% | A |
| Best Practices | 95% | A |
| Functionality | 100% | A+ |
| Code Quality | 93% | A |
| Security | 100% | A+ |
| Performance | 100% | A+ |
| Consistency | 95% | A |
| Build Success | 100% | A+ |

**Overall Grade: A (97%)**

Score deductions:
- Spec Compliance (–8%): missing `/run/wrappers/bin` in explicit PATH prefix; missing `2>/dev/null || true` on systemctl
- Code Quality (–7%): shorter comment than spec recommended
- Consistency (–5%): PATH string format diverges slightly from spec (appends `$PATH` vs. hardcoded full string)

---

## 7. Verdict

### ✅ PASS

Both files implement the required fixes correctly. All build validations pass. The minor deviations from the spec are either improvements (appending `$PATH` is safer than hardcoding) or negligible omissions that carry no functional risk. The root cause (`bare sed` in a bare module attrset) is permanently eliminated. The safety-net PATH guard is in place for legacy template users.

**No refinement required.**
