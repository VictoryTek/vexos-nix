# Review: Use Mainline VirtualBox Guest Kernel Modules

**Feature:** `vbox_mainline_modules`
**Spec:** `.github/docs/subagent_docs/vbox_mainline_modules_spec.md`
**Modified Files:** `modules/gpu/vm.nix`, `modules/gpu/vanilla-vm.nix`

---

## Specification Compliance

Both files: kernel pin removed, `virtualisation.virtualbox.guest.use3rdPartyModules = false;`
added next to the existing guest-additions lines, comment explains why. Matches spec exactly.

## Orphan Cleanup

Removing the kernel pin made `pkgs` the only unused function argument in both files
(it had no other use in either file). Removed from both signatures
(`{ config, lib, pkgs, ... }:` → `{ config, lib, ... }:` in `vm.nix`;
`{ lib, pkgs, ... }:` → `{ lib, ... }:` in `vanilla-vm.nix`). No other orphans introduced.

## Module Architecture Pattern

No new `lib.mkIf` guards added. No new files needed — both edits are in-place changes to
existing role-addition files already scoped to `gpu = "vm"` hosts. Consistent with Option B.

## Governance Checks (run on this machine — see Build Validation note below)

| Check | Result |
|-------|--------|
| `hardware-configuration.nix` not tracked (`git ls-files hardware-configuration.nix`) | PASSED — empty output |
| `system.stateVersion` unchanged | PASSED — no `configuration-*.nix` file touched |
| New flake inputs declare `follows` | N/A — no flake input changes |
| Diff scope | Only `modules/gpu/vm.nix` and `modules/gpu/vanilla-vm.nix` changed |

## Build Validation — NOT EXECUTED (environment limitation)

This session is running on a Windows development machine with no `nix` or `sudo` binaries
available (`which nix` / `which sudo` both fail to resolve a usable Nix toolchain). The
CLAUDE.md-mandated `nix flake show --impure` and `sudo nixos-rebuild dry-build --flake
.#vexos-desktop-{amd,nvidia,vm}` (plus `.#vexos-server-vm` since this change touches a
server-role host) **could not be run from this machine**. This is a structural gap, not a
skipped step — Phase 6 preflight on the actual NixOS host is still required before this is
considered CI-ready.

**Action for the user:** on the target host, run:
```
nix flake show --impure
sudo nixos-rebuild dry-build --flake .#vexos-server-vm
sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm
sudo nixos-rebuild dry-build --flake .#vexos-vanilla-vm
bash scripts/preflight.sh
```

## Out-of-Scope Item Noted (not touched)

`modules/gpu/vm.nix`'s `services.scx.enable = lib.mkForce false;` still carries a stale
comment ("VM is pinned to 6.6 LTS") that predates this change and was already inaccurate
before this fix (the actual pin was 6.12, which already met the `>= 6.12` scx requirement
the comment cites). Left untouched per the user's original request scope — flagging per
CLAUDE.md's Surgical Changes rule.

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | Not verifiable on this host | N/A |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | Not run — no Nix toolchain on this machine | BLOCKED |

**Overall: PASS pending user-run Phase 6 preflight on the NixOS host.**
