# Host Normalization — Review & Quality Assurance

**Reviewer:** QA Subagent  
**Date:** 2026-04-26  
**Spec:** `.github/docs/subagent_docs/host_normalization_spec.md`  
**Modified files:** 26 (1 flake.nix + 20 hosts/ + 5 modules/gpu/)

---

## Sub-task A: asus.nix on all desktop hosts

| Check | Result |
|---|---|
| All 4 desktop hosts import `../modules/asus.nix` | ✅ PASS — `desktop-amd:9`, `desktop-intel:9`, `desktop-nvidia:9`, `desktop-vm:20` |
| No non-desktop host imports asus.nix | ✅ PASS — `grep -rn 'asus.nix' hosts/` returns only desktop files |
| `nix eval ... vexos-desktop-intel ... services.asusd.enable` → `true` | ✅ PASS |
| `nix eval ... vexos-desktop-vm ... services.asusd.enable` → `true` | ✅ PASS |
| `nix eval ... vexos-htpc-amd ... services.asusd.enable` → `false` | ✅ PASS (not imported) |

**Verdict:** PASS — no issues.

---

## Sub-task B: Variant stamp in mkHost

| Check | Result |
|---|---|
| `mkHost` accepts `name` parameter | ✅ PASS — `mkHost = { name, role, gpu, nvidiaVariant ? null }:` |
| `variantModule` uses `environment.etc` for non-stateless | ✅ PASS |
| `variantModule` uses `vexos.variant` for stateless | ✅ PASS |
| Call site passes `inherit (h) name role gpu;` | ✅ PASS — line 244 |
| Inline `environment.etc."nixos/vexos-variant"` removed from all 4 htpc hosts | ✅ PASS — `grep -rn 'vexos-variant' hosts/htpc-*.nix` → 0 results |
| Inline `vexos.variant` removed from all 4 stateless hosts | ✅ PASS — `grep -rn 'vexos.variant' hosts/stateless-*.nix` → 0 results |

### Variant stamp spot-check (nix eval):

| Configuration | Expected | Actual | Status |
|---|---|---|---|
| `vexos-desktop-amd` | `"vexos-desktop-amd\n"` | `"vexos-desktop-amd\n"` | ✅ |
| `vexos-htpc-nvidia` | `"vexos-htpc-nvidia\n"` | `"vexos-htpc-nvidia\n"` | ✅ |
| `vexos-server-intel` | `"vexos-server-intel\n"` | `"vexos-server-intel\n"` | ✅ |
| `vexos-headless-server-vm` | `"vexos-headless-server-vm\n"` | `"vexos-headless-server-vm\n"` | ✅ |
| `vexos-stateless-amd` (env.etc) | `"N/A"` (expected — uses activation script) | `"N/A"` | ✅ |
| `vexos-stateless-amd` (vexos.variant) | `"vexos-stateless-amd"` | `"vexos-stateless-amd"` | ✅ |
| `vexos-htpc-nvidia-legacy535` | `"vexos-htpc-nvidia-legacy535\n"` | `"vexos-htpc-nvidia-legacy535\n"` | ✅ |

**Verdict:** PASS — all stamps are correct. Legacy variants now get their exact output name (improvement over previous behaviour where they inherited the base host's stamp).

---

## Sub-task C: VirtualBox guest in GPU modules

| Check | Result |
|---|---|
| `modules/gpu/amd.nix` contains `virtualisation.virtualbox.guest.enable = lib.mkForce false;` | ✅ PASS (line 37) |
| `modules/gpu/nvidia.nix` contains `virtualisation.virtualbox.guest.enable = lib.mkForce false;` | ✅ PASS (line ~79) |
| `modules/gpu/intel.nix` contains `virtualisation.virtualbox.guest.enable = lib.mkForce false;` | ✅ PASS (line ~53) |
| `modules/gpu/amd-headless.nix` contains `virtualisation.virtualbox.guest.enable = lib.mkForce false;` | ✅ PASS (line ~38) |
| `modules/gpu/intel-headless.nix` contains `virtualisation.virtualbox.guest.enable = lib.mkForce false;` | ✅ PASS (line ~38) |
| `modules/gpu/nvidia-headless.nix` does NOT contain the line (inherits from nvidia.nix via import) | ✅ PASS — `imports = [ ./nvidia.nix ];` confirmed |
| `modules/gpu/vm.nix` does NOT contain `mkForce false` (keeps `guest.enable = true`) | ✅ PASS |
| `grep -rn 'virtualbox.guest' hosts/` → ZERO results | ✅ PASS |
| `nix eval ... vexos-desktop-amd ... virtualbox.guest.enable` → `false` | ✅ PASS |
| `nix eval ... vexos-desktop-vm ... virtualbox.guest.enable` → `true` | ✅ PASS |

All 5 GPU modules include explanatory comments about the purpose of the force-disable.

**Verdict:** PASS — no issues.

---

## Sub-task D: VM hostName removed

| Check | Result |
|---|---|
| `grep -rn 'networking.hostName' hosts/*-vm.nix` → ZERO results | ✅ PASS |
| `nix eval ... vexos-desktop-vm ... networking.hostName` → `"vexos"` | ✅ PASS (inherited from `modules/network.nix` line 10) |

**Verdict:** PASS — no issues.

---

## Collateral Damage Assessment

| Check | Result |
|---|---|
| `git diff --name-only HEAD` shows exactly 26 files | ✅ PASS (confirmed via `wc -l`) |
| `modules/gpu/nvidia-headless.nix` NOT modified | ✅ PASS (absent from diff) |
| `modules/gpu/vm.nix` NOT modified | ✅ PASS (absent from diff) |
| No `configuration-*.nix` modified | ✅ PASS |
| No `modules/gnome*`, `modules/branding.nix`, `home-*.nix` modified | ✅ PASS |
| No `README.md`, `justfile`, `scripts/preflight.sh` modified | ✅ PASS |

**Verdict:** PASS — zero collateral damage.

---

## Overall Flake Health

| Check | Result |
|---|---|
| `nix eval ... builtins.length (builtins.attrNames cfgs)` → 30 | ✅ PASS |
| `nix flake check --no-build` | ⚠️ Expected failure — `/etc` absolute path forbidden in pure mode (pre-existing; requires `--impure`) |
| Individual attribute evaluation across 6 diverse configs | ✅ PASS — all attributes resolve correctly |
| `boot.loader.grub.devices` assertion on `system.build.toplevel` | ⚠️ Pre-existing — host `/etc/nixos/hardware-configuration.nix` doesn't set grub devices for full build; irrelevant to this change |

**Verdict:** PASS — flake health unchanged by this implementation.

---

## Host File Minimality Check

### Representative samples:

**`hosts/desktop-amd.nix`** (non-VM desktop):
- ✅ `configuration-desktop.nix` import
- ✅ `modules/gpu/amd.nix` import
- ✅ `modules/asus.nix` import (desktop-only)
- ✅ `distroName` only other content
- ✅ No boilerplate

**`hosts/desktop-vm.nix`** (VM):
- ✅ `configuration-desktop.nix` import
- ✅ `modules/gpu/vm.nix` import
- ✅ `modules/asus.nix` import (desktop-only)
- ✅ `distroName` + bootloader guidance comments (appropriate for VM)
- ✅ No boilerplate (no hostName, no vbox-guest, no variant stamp)

**`hosts/htpc-amd.nix`** (HTPC):
- ✅ `configuration-htpc.nix` import
- ✅ `modules/gpu/amd.nix` import
- ✅ `distroName` only other content
- ✅ No boilerplate (no vbox-guest, no variant stamp, no hostName)

**`hosts/stateless-amd.nix`** (Stateless):
- ✅ `configuration-stateless.nix` import
- ✅ `modules/gpu/amd.nix` import
- ✅ `modules/stateless-disk.nix` import
- ✅ Role-specific `vexos.stateless.disk` config (required)
- ✅ `distroName`
- ✅ No boilerplate (no vbox-guest, no variant stamp, no hostName)

**Verdict:** PASS — all host files are minimal and normalized.

---

## Score Table

| Category | Score | Grade |
|---|---|---|
| Specification Compliance | 100% | A+ |
| Best Practices | 98% | A+ |
| Functionality | 100% | A+ |
| Code Quality | 98% | A+ |
| Security | 100% | A+ |
| Performance | 100% | A+ |
| Consistency | 100% | A+ |
| Build Success | 95% | A |

**Overall Grade: A+ (99%)**

### Notes on scores:

- **Best Practices (98%):** Minor — GPU modules each have their own copy of the vbox-guest comment. Acceptable per spec since amd-headless and intel-headless don't inherit from their base modules. Could be improved in a future refactor.
- **Build Success (95%):** `nix flake check` requires `--impure` (pre-existing architectural constraint, not introduced by this change). All impure evaluations succeed. `system.build.toplevel` assertion is a pre-existing host-specific limitation.

---

## Verdict: **PASS**

All 4 sub-tasks are correctly implemented per specification. Zero collateral damage. All 30 flake outputs resolve. Host files are normalized and minimal. The variant stamp mechanism is correctly split between `environment.etc` (non-stateless) and `vexos.variant` (stateless) as designed.

No CRITICAL or RECOMMENDED findings.
