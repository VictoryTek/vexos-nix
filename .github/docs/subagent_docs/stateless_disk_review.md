# Stateless Disk Automation — Code Review

**Feature:** `stateless_disk`
**Date:** 2026-04-10
**Reviewer:** Phase 3 Review Subagent
**Spec:** `.github/docs/subagent_docs/stateless_disk_spec.md`

---

## Build Validation

```
nix flake check
```

**Result:** UNAVAILABLE — `nix` binary not found in WSL Ubuntu on this machine.

Manual Nix syntax review was performed instead. All files reviewed for:
- Correct brace/bracket matching
- Valid Nix expression structure
- Proper use of `lib.*` functions
- Consistent indentation and attribute path correctness

**Manual syntax verdict:** No syntax errors detected in any reviewed file.

---

## Findings

### CRITICAL

None found.

---

### WARNING

#### W-1 — `configuration-stateless.nix`: Outdated impermanence comment

**File:** `configuration-stateless.nix`
**Severity:** WARNING
**Category:** Consistency / Documentation

The comment above `vexos.impermanence.enable = true` still reads:

```nix
# Requires hardware-configuration.nix to declare / as tmpfs and
# /persistent as a neededForBoot btrfs subvolume (see impermanence_spec.md).
```

This is directly contradicted by the new implementation:

- `modules/impermanence.nix` now **automatically** declares `fileSystems."/"` as tmpfs inside `config = lib.mkIf cfg.enable { ... }` — no manual action required.
- `modules/stateless-disk.nix` now **automatically** sets `neededForBoot = true` on `/persistent` and `/nix` via `lib.mkForce` — no manual action required.

The comment is not within the spec's stated scope of files to modify (`configuration-stateless.nix` was not in the modification list), but it directly contradicts the purpose of this change and could mislead a user into adding conflicting `fileSystems."/"` entries to `hardware-configuration.nix`, causing an evaluation conflict.

**Recommended fix:**

```nix
# ---------- Impermanence ----------
# Enable tmpfs-rooted ephemeral filesystem for the stateless role.
# / is wiped on every reboot; only /nix and /persistent survive.
# Disk layout is handled declaratively by modules/stateless-disk.nix (disko).
# No manual hardware-configuration.nix edits are required.
vexos.impermanence.enable = true;
```

---

#### W-2 — `flake.nix` + `modules/stateless-disk.nix`: Redundant double import of disko module

**Files:** `flake.nix`, `modules/stateless-disk.nix`
**Severity:** WARNING
**Category:** Consistency / Code Quality

`inputs.disko.nixosModules.disko` is imported in two places for every stateless build:

1. **`flake.nix`** — unconditionally in the `modules` list of all four `vexos-stateless-*` nixosConfigurations:
   ```nix
   modules = commonModules ++ [
     ./hosts/stateless-amd.nix
     inputs.disko.nixosModules.disko   ← import #1
   ];
   ```

2. **`modules/stateless-disk.nix`** — conditionally via `lib.optionals cfg.enable`:
   ```nix
   imports = lib.optionals cfg.enable [
     inputs.disko.nixosModules.disko   ← import #2 (fires when enable=true)
   ];
   ```

Since all four stateless hosts set `vexos.stateless.disk.enable = true`, import #2 always fires for stateless configs, resulting in the same module value being added twice to the module list.

**Impact:** NixOS deduplicates modules by reference equality for non-path modules. Since both references point to the same `inputs.disko.nixosModules.disko` Nix value, the module system handles this correctly — the module is only evaluated once. There is **no functional defect**.

However, this is architecturally redundant and creates confusion about which import is authoritative. The `spec section 13` explicitly required adding disko to `flake.nix`, and `spec section 10` showed the module's conditional import as well. Both are correct individually; the redundancy is a spec design artefact.

**Note:** The spec explicitly required both, so this is not a spec deviation. Flagged for awareness.

**Recommended fix (optional):** Remove `inputs.disko.nixosModules.disko` from the per-nixosConfiguration `modules` list in `flake.nix` and rely solely on the conditional import in `modules/stateless-disk.nix`. This makes `stateless-disk.nix` fully self-contained — enabling the disk module automatically brings in disko, with no action required in `flake.nix` beyond the input declaration.

---

#### W-3 — `scripts/stateless-setup.sh`: Missing `-e` in `set -uo pipefail`

**File:** `scripts/stateless-setup.sh`
**Severity:** WARNING
**Category:** Best Practices / Safety

The script uses `set -uo pipefail` but omits `-e`. The spec section 14 explicitly specified `set -uo pipefail`, so this is a **spec-conformant choice**, not a deviation.

However, for a **destructive disk-formatting script**, the absence of `-e` means that a non-zero exit code from a non-pipe command (e.g., `nixos-generate-config` or `nixos-install` failing) will **not** abort the script. Subsequent steps could run against a partially configured system. This is a genuine operational safety concern even if it matches the spec.

**Example risk:** If `nixos-generate-config --no-filesystems --root /mnt` fails silently, the template flake download and `nixos-install` will still proceed against a `/mnt/etc/nixos/` without a `hardware-configuration.nix`.

**Recommended fix:**

```bash
set -euo pipefail
```

**Note:** The `nixos-install` step at the end uses `sudo nixos-install ...` directly (not in an `if` block), so a build failure there WILL exit non-zero and abort the script. However, intermediate steps are still unguarded.

---

### RECOMMENDATION

#### R-1 — `modules/stateless-disk.nix`: Missing assertion for empty `cfg.device`

The `device` option accepts any `lib.types.str` including `""`. An empty string passed to disko as the disk device would cause a cryptic disko error at format time rather than a clear NixOS evaluation failure.

**Recommended addition** inside `config = lib.mkIf cfg.enable { ... }`:

```nix
assertions = [
  {
    assertion = cfg.device != "";
    message = ''
      vexos.stateless.disk.enable = true requires vexos.stateless.disk.device
      to be set to a valid block device path (e.g. "/dev/nvme0n1").
      It is currently set to an empty string.
    '';
  }
];
```

---

#### R-2 — Consider setting `vexos.stateless.disk.enable = true` in `configuration-stateless.nix`

Currently, `enable = true` must be set in each of the four stateless host files. Since the stateless role always requires the disk module (by definition), centralizing this in `configuration-stateless.nix` would be more DRY and make it impossible to accidentally create a stateless host without the disk module enabled.

---

#### R-3 — `scripts/stateless-setup.sh`: No pre-disko LUKS passphrase advisory

The spec explicitly chose to let disko handle the interactive LUKS passphrase prompt (rather than pre-prompting and using a temp file). This is correct. However, the script does not print any advisory before the disko step about what the user will be asked for during formatting (a passphrase prompt will appear mid-operation without forewarning in the flow).

**Recommended addition** before the disko step (non-VM path only):

```bash
if [ "$LUKS_BOOL" = "true" ]; then
  echo ""
  echo -e "${YELLOW}${BOLD}LUKS encryption:${RESET} disko will prompt you for a passphrase"
  echo "  during formatting. You will be asked to enter it twice."
  echo "  Store this passphrase securely — loss means unrecoverable data."
  echo ""
fi
```

---

## Full Checklist Results

### A. `modules/impermanence.nix`

| Check | Result |
|-------|--------|
| PREREQUISITES block removed | ✅ PASS |
| `fileSystems."/"` inside `config = lib.mkIf cfg.enable { ... }` | ✅ PASS |
| tmpfs options sensible (device=none, fsType=tmpfs, size, mode) | ✅ PASS |
| Both assertions reference correct persistent path | ✅ PASS |
| `inputs.impermanence.nixosModules.impermanence` conditionally imported | ✅ PASS |
| No Nix syntax errors | ✅ PASS |

---

### B. `modules/stateless-disk.nix`

| Check | Result |
|-------|--------|
| Module signature `{ config, lib, inputs, ... }:` | ✅ PASS |
| Options under `options.vexos.stateless.disk.*` | ✅ PASS |
| `enable` defaults to `false` | ✅ PASS |
| `device` type is `lib.types.str` | ✅ PASS |
| `enableLuks` defaults to `true` | ✅ PASS |
| `inputs.disko.nixosModules.disko` conditionally imported | ✅ PASS |
| disko layout under `disko.devices.disk.main` | ✅ PASS |
| EFI partition: 512MiB, vfat, `/boot` | ✅ PASS |
| LUKS2 partition when `cfg.enableLuks = true` | ✅ PASS |
| Btrfs @nix → /nix, @persist → /persistent | ✅ PASS |
| `/nix` and `/persistent` `neededForBoot = true` via `lib.mkForce` | ✅ PASS |
| VM path (enableLuks=false): plain Btrfs, no LUKS | ✅ PASS |
| No Nix syntax errors | ✅ PASS |
| `cfg.device` non-empty assertion | ⚠️ MISSING (R-1) |

---

### C. `template/stateless-disko.nix`

| Check | Result |
|-------|--------|
| Standalone disko config (not a NixOS module) | ✅ PASS |
| Accepts `disk` parameter (function default arg) | ✅ PASS |
| Layout matches `modules/stateless-disk.nix` | ✅ PASS |
| Compatible with disko CLI `--arg` invocation | ✅ PASS |
| No Nix syntax errors | ✅ PASS |

---

### D. `scripts/stateless-setup.sh`

| Check | Result |
|-------|--------|
| Starts with `#!/usr/bin/env bash` | ✅ PASS |
| Has `set -euo pipefail` | ⚠️ WARNING — has `set -uo pipefail` (spec W-3) |
| Lists block devices before prompting | ✅ PASS (`lsblk -d -o NAME,SIZE,MODEL,TRAN`) |
| Double-confirmation before destructive op | ✅ PASS (re-type device path) |
| LUKS passphrase prompt before disko | ℹ️ DELEGATED to disko (per spec §14) |
| Passphrase temp file mode 600 + trap | ℹ️ NOT REQUIRED (per spec §14) |
| Runs disko with correct arguments | ✅ PASS |
| `nixos-generate-config --no-filesystems --root /mnt` | ✅ PASS |
| GPU variant selection | ✅ PASS |
| `nixos-install --flake ...#vexos-stateless-<variant>` | ✅ PASS |
| No bash syntax errors | ✅ PASS |
| Repo at /mnt/etc/nixos via template flake | ✅ PASS |

---

### E. `flake.nix`

| Check | Result |
|-------|--------|
| `disko` input with `url = "github:nix-community/disko/latest"` | ✅ PASS |
| `inputs.nixpkgs.follows = "nixpkgs"` | ✅ PASS |
| `disko` in outputs destructuring | ✅ PASS |
| `inputs.disko.nixosModules.disko` in all 4 stateless nixosConfigurations | ✅ PASS |
| No syntax errors | ✅ PASS |

---

### F. Stateless host files

| Check | AMD | NVIDIA | Intel | VM |
|-------|-----|--------|-------|-----|
| `../modules/stateless-disk.nix` imported | ✅ | ✅ | ✅ | ✅ |
| `vexos.stateless.disk.enable = true` | ✅ | ✅ | ✅ | ✅ |
| `vexos.stateless.disk.device` set | ✅ `lib.mkDefault "/dev/nvme0n1"` | ✅ `lib.mkDefault "/dev/nvme0n1"` | ✅ `lib.mkDefault "/dev/nvme0n1"` | ✅ `/dev/vda` |
| VM: `enableLuks = false` | N/A | N/A | N/A | ✅ |
| No syntax errors | ✅ | ✅ | ✅ | ✅ |

---

### G. Security review of `stateless-setup.sh`

| Check | Result |
|-------|--------|
| LUKS passphrase NOT echoed to terminal | ✅ PASS (disko handles interactively) |
| Temp file with passphrase mode 600 | ℹ️ Not applicable — passphrase delegated to disko per spec |
| Temp file deleted after use (trap) | ℹ️ Not applicable |
| No injection vulnerabilities | ✅ PASS — device path never interpolated raw into commands |
| Disk device validated before use | ✅ PASS — `/dev/` prefix check AND `[ -b "$DISK_INPUT" ]` block device check |

---

### H. Interaction between `impermanence.nix` and `stateless-disk.nix`

| Check | Result |
|-------|--------|
| Option namespaces don't conflict (`vexos.impermanence` vs `vexos.stateless.disk`) | ✅ PASS |
| tmpfs `"/"` in impermanence.nix and disko layout don't conflict | ✅ PASS — separate mount points |
| `neededForBoot` assertion in impermanence satisfied by `lib.mkForce` in stateless-disk | ✅ PASS |

---

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 92% | A- |
| Best Practices | 83% | B |
| Functionality | 94% | A |
| Code Quality | 90% | A- |
| Security | 85% | B |
| Performance | 96% | A |
| Consistency | 82% | B- |
| Build Success | 78% | C+ |

**Overall Grade: B+ (88%)**

> Build Success downgraded from A to C+ solely due to inability to run `nix flake check` in
> this environment. Manual syntax review found no errors. If `nix flake check` passes on the
> target system, Build Success should be rated A (95%+).

---

## Summary

The implementation is well-structured and faithfully follows the specification. All critical
requirements from the spec have been met:

- The PREREQUISITES comment block in `impermanence.nix` has been removed and replaced with a
  concise reference comment
- `fileSystems."/"` is now declared programmatically inside `config = lib.mkIf cfg.enable`
- `modules/stateless-disk.nix` implements the full disko disk layout with correct LUKS2 + Btrfs
  subvolume structure, proper `neededForBoot` flags, and VM bypass path
- `template/stateless-disko.nix` is a correct standalone parameterized disko config
- `scripts/stateless-setup.sh` correctly delegates LUKS passphrase handling to disko
  (per spec section 14), validates the disk device, and requires double confirmation
- `flake.nix` correctly adds disko as an input and imports the disko module in all four
  stateless configurations
- All four stateless host files correctly import the new module and set the required options
- `scripts/install.sh` includes the required notice directing stateless users to
  `stateless-setup.sh` for initial installs

No CRITICAL issues were found. Three WARNINGs and three RECOMMENDATIONs are noted above,
the most impactful being the outdated comment in `configuration-stateless.nix` (W-1) which
contradicts the purpose of this entire change.

---

## Verdict

**PASS**

The implementation is ready to proceed. Address WARNING W-1 (outdated comment in
`configuration-stateless.nix`) and W-3 (missing `-e` in `set -uo pipefail`) before the
next system rebuild to avoid user confusion and improve script reliability.
