# VM guest platform split — Review

Spec: `.github/docs/subagent_docs/vm_platform_split_spec.md`

## Modified files

- `modules/gpu/vm-guest-additions.nix`
- `modules/gpu/vm.nix`
- `modules/gpu/vanilla-vm.nix`
- `hosts/vanilla-vm.nix`
- `template/features.nix`
- `scripts/install.sh`
- `justfile`

## Second defect found — spec gap, reported by the user

**`just switch` had no VM-platform handling at all.**

The spec's §3.5 covered only `scripts/install.sh`. But `just switch` also selects
the GPU variant post-install, so switching *to* a `vm` variant on a VirtualBox
host would silently leave `vexos.vm.platform` unset — falling back to the
`"qemu"` default and dropping guest additions on the next rebuild, with no
interactive way to set it. A genuine incompleteness in the delivered change, not
a deliberate omission.

Fix, mirroring the existing desktop-environment prompt in the same recipe:

- New optional 5th parameter — `switch role="" variant="" flake="" de="" vmp=""`
  — so `just switch desktop vm "" "" virtualbox` works non-interactively, and
  the interactive path prompts whenever `VARIANT = "vm"`.
- Extracted `_features_set <key> <value>` inside the recipe and routed **both**
  `vexos.desktop.environment` and `vexos.vm.platform` through it. Same refactor,
  same justification as `install.sh`: a second consumer now exists. The DE block
  drops from ~28 lines to 3.
- Reads the currently-active platform from `features.nix` first, so a real
  change can be distinguished from a no-op.
- A platform change is routed through the existing `nixos-rebuild boot` +
  reboot path, alongside a DE change but for a different reason: it swaps
  `boot.kernelPackages` (VirtualBox pins 6.18, QEMU follows the role's own
  kernel) and swaps the guest-additions services, so a live switch would leave
  the running kernel mismatched against the new generation's modules.
- Fixed the queued-boot success message, which printed `${DESKTOP_ENV}`
  unconditionally and would have been blank for a non-desktop role. Now prints
  `${TARGET}`.

Validation: `just --list` parses; the `switch` recipe body extracted via
`just --show switch` with `{{…}}` interpolations substituted passes `bash -n`;
the new signature is confirmed present.

## Defect found and fixed during review

**`hosts/vanilla-vm.nix` silently bypassed the entire gate — and was already
bypassing `modules/gpu/vanilla-vm.nix` before this change.**

Caught by evaluation, not by reading: the first verification run returned
`vexos-vanilla-vm … vbox=1` on the `qemu` default. Root cause was two layers
deep:

1. `mkHost` (`flake.nix:278-312`) composes each system from
   `./hosts/<role>-<gpu>.nix`, and each host file is responsible for importing
   its own GPU module. Every `hosts/*-vm.nix` does this — except
   `hosts/vanilla-vm.nix`, which instead **inlined a partial copy** of the
   guest-additions settings (`qemuGuest`, `spice-vdagentd`,
   `virtualbox.guest.enable`, `virtualbox.guest.dragAndDrop`).
2. Consequently `modules/gpu/vanilla-vm.nix` was **dead code for the in-repo
   `vexos-vanilla-vm` output**. It reached only external consumers, via
   `flake.nix:485` `nixosModules.gpuVanillaVm` → `template/etc-nixos-flake.nix:385`.
   The in-repo and template builds of the same variant were therefore not
   equivalent: the in-repo one had no virtio/QXL initrd modules and no
   `cpuFreqGovernor` override.

The inlined `virtualisation.virtualbox.guest.enable = true` outranked nothing —
it simply was the only definition, so gating the module's copy had no effect.

Fix: `hosts/vanilla-vm.nix` now imports `../modules/gpu/vanilla-vm.nix` like
every other VM host file, and the duplicated block is removed. This both
restores the gate and closes the in-repo/template divergence.

An interim state during review (duplication removed but the import not yet
added) left `vexos-vanilla-vm` with no guest additions at all; caught by the
same evaluation loop before completion.

## Build validation

`nix` is not available in the Windows working directory. **WSL Ubuntu on this
machine has Nix 2.34.1**, which ran everything below against the real flake.

### Flake structure

| Check | Result |
|---|---|
| `nix flake show --impure` | PASS — **30** `nixosConfigurations`, unchanged |

### Per-variant evaluation — `vexos.vm.platform = "qemu"` (default)

| Variant | kernel | vbox guest | qemuGuest | spice |
|---|---|---|---|---|
| `vexos-desktop-vm` | **7.2** | false | true | true |
| `vexos-stateless-vm` | **7.2** | false | true | true |
| `vexos-server-vm` | 6.18.46 | false | true | true |
| `vexos-headless-server-vm` | 6.18.46 | false | true | true |
| `vexos-htpc-vm` | 6.12.105 | false | true | true |
| `vexos-vanilla-vm` | 6.18.46 | false | true | true |

`vexos-desktop-amd` (non-VM control) evaluates to kernel **7.2** — confirming
`desktop-vm` now matches bare metal instead of trailing it at 6.18. Every
kernel result matches the spec's §3.4 prediction exactly.

### Per-variant evaluation — `vexos.vm.platform = "virtualbox"`

| Variant | kernel | vbox guest | dragAndDrop | qemuGuest |
|---|---|---|---|---|
| `vexos-desktop-vm` | 6.18.46 | true | true | false |
| `vexos-vanilla-vm` | 6.18.46 | true | true | false |

Identical to pre-change behaviour for VirtualBox hosts, as required.

### Overlay gating

`config.nixpkgs.overlays` length: **3** under `virtualbox`, **2** under `qemu`.
Confirms the `virtualboxGuestAdditions` patch overlay is genuinely gated and
that `lib.mkIf` around `nixpkgs.overlays` behaves as the spec assumed — this
was listed as a risk and is now verified rather than presumed.

### Full closure evaluation

`config.system.build.toplevel.drvPath` forced (CLAUDE.md's stated equivalent of
`nix flake check --no-build` for a single target; `nix flake check` itself is
FORBIDDEN and was not run):

| Target | Platform | Result |
|---|---|---|
| `vexos-desktop-vm` | qemu | PASS |
| `vexos-vanilla-vm` | qemu | PASS |
| `vexos-desktop-amd` | n/a | PASS |
| `vexos-desktop-vm` | virtualbox | PASS |
| `vexos-vanilla-vm` | virtualbox | PASS |

### Repository invariants

| Check | Result |
|---|---|
| `git ls-files hardware-configuration.nix` | PASS — empty |
| `system.stateVersion` changed in any `configuration-*.nix` | PASS — none |
| `flake.nix` / `flake.lock` modified | PASS — untouched, no new inputs |
| `bash -n scripts/install.sh` | PASS |

## Phase 6 — Preflight

`bash scripts/preflight.sh` run in WSL with `jq` and `nixpkgs-fmt` supplied:

```
Preflight PASSED — safe to push.
PREFLIGHT_EXIT=0
```

**Exit code 0, but two stages could not run here and this is not a complete
gate:**

- **`[2/8] nixos-rebuild dry-build` — SKIPPED.** Requires a NixOS host with
  `/etc/nixos/vexos-variant`. This is the one check that exercises the actual
  build, and it must be run by the user on the target machine.
- `[7e] gitleaks` — skipped, not installed. Unrelated to this change.

Stage `[6/8]` formatting is a WARN reporting **100 of 190** files — a
pre-existing repo-wide condition, not introduced here. `nixpkgs-fmt` was **not**
run across the repo; doing so would rewrite 100 files and violate the surgical
change rule. Per-file comparison against `HEAD`:

| File | HEAD | Working tree |
|---|---|---|
| `modules/gpu/vm-guest-additions.nix` | clean | clean *(regressed by one aligned `=`, fixed)* |
| `modules/gpu/vm.nix` | non-conformant | non-conformant *(pre-existing)* |
| `modules/gpu/vanilla-vm.nix` | non-conformant | non-conformant *(pre-existing)* |
| `hosts/vanilla-vm.nix` | clean | clean |
| `template/features.nix` | clean | clean |

Stage `[7a]`'s hardcoded-secret WARN
(`modules/server/vexboard.nix:90`, a documented placeholder) is pre-existing
and untouched by this change.

## Score table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 95% | A |
| Functionality | 100% | A |
| Code Quality | 92% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 98% | A |
| Build Success | 85% | B |

**Overall Grade: A (96%)**

Build Success is marked down solely because `nixos-rebuild dry-build` cannot run
in this environment. Everything reachable without a NixOS host passed, including
full `toplevel.drvPath` evaluation of five configuration shapes.

## Result

**PASS**, with one qualification that is not mine to close: Phase 6 is
**incomplete**, not failed. The user must run
`sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm` (or
`bash scripts/preflight.sh`) on a NixOS host before pushing.

## Notes for the follow-up Hyprland/Noctalia change

- `modules/gpu/vm.nix:94` still has `before = [ "greetd.service" ]` on the
  render-node check. If the Noctalia work keeps greetd this stays valid; if the
  display manager changes, that reference needs updating.
- The same file's render-node warning text still asserts the missing-render-node
  theory that the user's Omarchy/CachyOS evidence contradicts. Left untouched
  here — it is a warning string, not behaviour, and rewriting it belongs with
  the Hyprland change that re-tests the premise.
- `.github/docs/subagent_docs/hyprland_traditional_session_spec.md` is now
  **stale**: it specifies SDDM, which the user superseded in favour of the
  Noctalia family. It must be revised before Phase 2 of that change.
