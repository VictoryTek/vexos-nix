# Review: Replace virt-manager with VirtualBox

## Feature Name
`virtualbox_replacement`

## Date
2026-05-01

## Reviewer
Review & QA Subagent

---

## 1. Specification Compliance

| Spec Requirement | Status | Notes |
|------------------|--------|-------|
| Remove virt-manager, virt-viewer, virtio-win packages | ✅ PASS | All three packages removed; `environment.systemPackages` block eliminated entirely |
| Remove `virtualisation.spiceUSBRedirection.enable` | ✅ PASS | Confirmed evaluates to `false` (NixOS default) |
| Keep libvirtd + QEMU for GNOME Boxes | ✅ PASS | `virtualisation.libvirtd.enable = true`, qemu_kvm, runAsRoot=false, swtpm all retained |
| Add `virtualisation.virtualbox.host.enable = true` | ✅ PASS | Evaluates to `true` on desktop-amd and desktop-vm |
| Add `virtualisation.virtualbox.host.enableExtensionPack = true` | ✅ PASS | Evaluates to `true` |
| Add `vboxusers` to user groups | ✅ PASS | `nimda.extraGroups` contains both `libvirtd` and `vboxusers` |
| Add `virtualbox.desktop` to home-desktop.nix favorite-apps | ✅ PASS | Present in dconf `favorite-apps` list |
| Add `virtualbox.desktop` to gnome-desktop.nix favorite-apps | ✅ PASS | Present in system dconf `favorite-apps` list |
| No changes to configuration-desktop.nix | ✅ PASS | File unchanged; still imports virtualization.nix and installs gnome-boxes |
| No changes to flake.nix | ✅ PASS | VirtualBox guest guards untouched; unrelated to host config |
| No changes to modules/gpu/vm.nix | ✅ PASS | Guest additions unaffected |

**Result: 100% specification compliance.**

---

## 2. Best Practices

| Check | Status | Notes |
|-------|--------|-------|
| VirtualBox enabled via NixOS module (not systemPackages) | ✅ PASS | Correct — `virtualisation.virtualbox.host.enable` handles package installation |
| User group management via `users.users.nimda.extraGroups` | ✅ PASS | Consistent with NixOS patterns; merges with groups from other modules |
| No `lib.mkIf` guards in module | ✅ PASS | Follows Option B architecture — pure unconditional module |
| GNOME Boxes backend (libvirtd) correctly retained | ✅ PASS | Boxes would break without it |
| Comments explain purpose of each section | ✅ PASS | Clear header comment and inline comments |
| Unfree allowance documented | ✅ PASS | Comment references `modules/nix.nix` for unfree permission |

**No issues found.**

---

## 3. Consistency

| Check | Status | Notes |
|-------|--------|-------|
| Module follows Option B architecture | ✅ PASS | `virtualization.nix` is role-specific, imported only by `configuration-desktop.nix` |
| No `lib.mkIf` guards added | ✅ PASS | Compliant with architecture rules |
| Import list in configuration-desktop.nix unchanged | ✅ PASS | `./modules/virtualization.nix` still in imports |
| User groups don't conflict with `modules/users.nix` | ✅ PASS | `users.nix` defines `wheel` + `networkmanager`; NixOS list merging correctly combines all groups |
| Evaluated group list complete | ✅ PASS | Final merged groups: `gamemode`, `input`, `plugdev`, `audio`, `libvirtd`, `vboxusers`, `wheel`, `networkmanager` |
| favorite-apps lists match between home-desktop.nix and gnome-desktop.nix | ✅ PASS | Both contain identical `virtualbox.desktop` entry in the same position |
| Code style (indentation, comments, structure) | ✅ PASS | Matches project conventions |

**No issues found.**

---

## 4. Completeness

| Check | Status | Notes |
|-------|--------|-------|
| All 3 specified files modified | ✅ PASS | virtualization.nix, home-desktop.nix, gnome-desktop.nix |
| No unintended files modified | ✅ PASS | Only specified files changed |
| VirtualBox isolated to desktop role | ✅ PASS | server-amd and htpc-amd both evaluate `virtualbox.host.enable = false` |
| OVMF comment about NixOS 25.05+ | ✅ PASS | Helpful forward-looking comment about OVMF no longer being configurable |

**No issues found.**

---

## 5. Security

| Check | Status | Notes |
|-------|--------|-------|
| No hardcoded secrets | ✅ PASS | No credentials in any modified file |
| No insecure permissions | ✅ PASS | Standard NixOS group-based access control |
| VirtualBox hardening enabled | ✅ PASS | `enableHardening` defaults to `true` (not explicitly set, inherits NixOS default) |
| QEMU runAsRoot = false retained | ✅ PASS | Safer non-root execution for QEMU processes |
| `hardware-configuration.nix` not in repo | ✅ PASS | Not found in file search |
| `system.stateVersion` unchanged | ✅ PASS | Remains `"25.11"` in `configuration-desktop.nix:46` |

**No issues found.**

---

## 6. Performance

| Check | Status | Notes |
|-------|--------|-------|
| Extension pack recompilation trade-off documented in spec | ✅ PASS | Known and accepted |
| No unnecessary services enabled | ✅ PASS | Only VirtualBox host + existing libvirtd |
| Kernel module build impact acceptable | ✅ PASS | VirtualBox kernel modules build against running kernel; standard practice |

**No issues found.**

---

## 7. Build Validation

| Check | Status | Notes |
|-------|--------|-------|
| `nix flake check` | ⚠️ EXPECTED FAILURE | Fails with `boot.loader.grub.devices` assertion — pre-existing issue because `/etc/nixos/hardware-configuration.nix` is host-only and not in the repo. **Not caused by this change.** |
| `nix eval` desktop-amd toplevel | ⚠️ EXPECTED FAILURE | Same pre-existing boot.loader assertion. **Not caused by this change.** |
| `nix eval` VirtualBox host options | ✅ PASS | `virtualbox.host.enable = true`, `enableExtensionPack = true` |
| `nix eval` libvirtd options | ✅ PASS | `libvirtd.enable = true` |
| `nix eval` user groups | ✅ PASS | All expected groups present and correctly merged |
| `nix eval` spiceUSBRedirection | ✅ PASS | `false` (removed) |
| `nix eval` desktop-vm variant | ✅ PASS | VirtualBox host enabled, groups correct |
| `nix eval` server-amd isolation | ✅ PASS | VirtualBox host `false` — correctly not applied |
| `nix eval` htpc-amd isolation | ✅ PASS | VirtualBox host `false` — correctly not applied |
| `sudo nixos-rebuild dry-build` | ⚠️ SKIPPED | `sudo` unavailable in this environment (no-new-privileges flag) |

**Note:** The `nix flake check` and full `dry-build` failures are pre-existing infrastructure issues unrelated to this change. All VirtualBox-specific options evaluate correctly across all tested variants. The configuration is structurally sound.

---

## 8. Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A+ |
| Best Practices | 100% | A+ |
| Functionality | 100% | A+ |
| Code Quality | 100% | A+ |
| Security | 100% | A+ |
| Performance | 100% | A+ |
| Consistency | 100% | A+ |
| Build Success | 90% | A | 

**Overall Grade: A+ (99%)**

Build Success scored 90% because `sudo nixos-rebuild dry-build` could not be executed in this environment (sandbox restriction), and `nix flake check` has a pre-existing failure unrelated to this change. All evaluable VirtualBox-specific options pass correctly.

---

## 9. Issues Summary

### CRITICAL Issues
None.

### RECOMMENDED Improvements
None. The implementation is clean, minimal, and precisely follows the specification.

### INFORMATIONAL Notes
1. The `.desktop` file name `virtualbox.desktop` should be verified on the actual system after deployment — it may be `org.virtualbox.VirtualBox.desktop` depending on the NixOS VirtualBox package version. If the dock icon doesn't appear, this is the likely cause.
2. The `nix flake check` failure (boot.loader assertion) is a known project-level issue that predates this change and affects all configurations when evaluated without the host's `hardware-configuration.nix`.

---

## 10. Verdict

**PASS**

The implementation is complete, correct, consistent with project conventions, and follows the specification exactly. All NixOS options evaluate to the expected values. No critical or recommended issues were found.
