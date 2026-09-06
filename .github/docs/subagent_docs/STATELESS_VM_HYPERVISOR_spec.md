# STATELESS_VM_HYPERVISOR — Specification

## Phase 1: Research & Specification

### Current state analysis

The desktop/htpc/server/vanilla install path (`scripts/install.sh`) asks the user
which hypervisor a VM guest runs under whenever the GPU variant is `vm`:

- `install.sh:529-558` — "Select your hypervisor" prompt → `VM_PLATFORM` (`qemu` | `virtualbox`)
- `install.sh:881-885` — when `VM_PLATFORM = virtualbox`, `features_set "vexos.vm.platform" "virtualbox"`
  writes `/etc/nixos/features.nix`
- `qemu` is the option default (`modules/gpu/vm-guest-additions.nix:50`), so a
  QEMU/Proxmox guest needs no file at all.

`vexos.vm.platform` is consumed only by `modules/gpu/vm-guest-additions.nix`
(imported by `modules/gpu/vm.nix` and `modules/gpu/vanilla-vm.nix`). `virtualbox`
enables the VirtualBox guest additions and pins the kernel to 6.18 LTS; `qemu`
keeps the role kernel and enables the QEMU guest agent + SPICE.

**The stateless role never reaches any of this:**

1. **No prompt.** For `ROLE = stateless` on a live ISO, `install.sh:466-482` hands
   off to `scripts/stateless-setup.sh` and `exit 0`s before its own hypervisor
   prompt. `scripts/stateless-setup.sh:110-132` and
   `scripts/migrate-to-stateless.sh:290-312` have their own GPU-variant prompt but
   no hypervisor follow-up — picking `vm` just sets `VARIANT=vm` and moves on.

2. **Nowhere to store the answer.** The stateless role does not import
   `/etc/nixos/features.nix`:
   - Repo: `flake.nix:271-276` — `roles.stateless.hostLocalModules =
     statelessUserOverrideModule` (no `featuresModule`).
   - Template: `template/etc-nixos-flake.nix:211-233` — `mkStatelessVariant` has no
     `lib.optional hasFeatures featuresFile` (unlike `mkHtpcVariant`,
     `_mkVariantWith`, etc.).
   - `justfile:1399-1410` `_require-desktop-role` documents this as deliberate:
     "features not supported there — neither role wires /etc/nixos/features.nix
     into its module set".

Net effect: `vexos-stateless-vm` always gets the `qemu` default and can never be a
VirtualBox guest, regardless of installer input.

### Problem definition

A user installing the stateless role into a VirtualBox VM is never asked which
hypervisor they use, and has no supported way to select VirtualBox guest
additions. The stateless VM path must reach functional parity with the
desktop VM path.

### Proposed solution architecture

Mirror the desktop path exactly, minimally:

1. **Add a hypervisor prompt** to `stateless-setup.sh` and `migrate-to-stateless.sh`,
   gated on `VARIANT = vm`, identical wording to `install.sh:541-556` (plain-prompt
   variant — these scripts have no `gum`).

2. **Write `features.nix` only for VirtualBox.** `qemu` is the option default; a
   QEMU/Proxmox guest gets no file, exactly like the desktop path. The file
   contains a single line: `vexos.vm.platform = "virtualbox";`.

3. **Wire a dedicated `/etc/nixos/vm-platform.nix` into the stateless role** in
   both flake definitions, via a new `statelessVmPlatformModule` (repo) /
   `hasVmPlatform` + `vmPlatformFile` (template), parallel to the existing
   `statelessUserOverrideModule` machinery. The file contains only
   `vexos.vm.platform = "virtualbox";`.

**Decision — mechanism (features.nix vs. a dedicated file):** use a dedicated
`vm-platform.nix`. Wiring `/etc/nixos/features.nix` wholesale into the stateless
role was implemented first and **rejected after evaluation**: the stateless role
does not import `modules/gaming.nix`, `modules/development.nix`, etc., so it does
not declare the `vexos.features.*` options. On any developer host that already
has a populated `features.nix` (e.g. `vexos.features.development.enable = true`),
`nix eval .#nixosConfigurations.vexos-stateless-vm` then fails with
`The option 'vexos.features' does not exist`. A dedicated file that only ever
carries `vexos.vm.platform` keeps the stateless role isolated from the desktop
feature-toggle surface. The `justfile` `_require-desktop-role` guard and
`template/features.nix` are left unchanged.

### Implementation steps (Module Architecture Pattern — Option B)

This change adds no NixOS modules and no `lib.mkIf` guards. It extends two flake
module lists and two installer scripts. `vexos.vm.platform` is a module-declared
toggle (the sanctioned carve-out per CLAUDE.md), already gated correctly inside
`modules/gpu/vm-guest-additions.nix`.

#### 1. `scripts/stateless-setup.sh`

- After the NVIDIA driver branch (~line 154), before the ASUS block, add a
  `VM_PLATFORM` prompt gated on `[ "$VARIANT" = "vm" ]`. Default unset; loop until
  `qemu` or `virtualbox`.
- In the installation summary (~lines 233-240), print `Hypervisor: <qemu|virtualbox>`
  when `VARIANT = vm`.
- After `stateless-user-override.nix` is written and **before**
  `git -C /mnt/etc/nixos add .`, when `[ "$VM_PLATFORM" = "virtualbox" ]`
  write `/mnt/etc/nixos/vm-platform.nix` containing only
  `{ vexos.vm.platform = "virtualbox"; }`.
  (`git add .` then tracks it; `.gitignore` does not exclude it.)
- In the `/persistent` copy list add:
  `sudo cp /mnt/etc/nixos/vm-platform.nix /mnt/persistent/etc/nixos/ 2>/dev/null || true`

#### 2. `scripts/migrate-to-stateless.sh`

- After the NVIDIA driver branch (~line 334) add the same `VM_PLATFORM` prompt.
- When `[ "$VM_PLATFORM" = "virtualbox" ]`, write `/etc/nixos/vm-platform.nix`
  with the same content, then `git -C /etc/nixos add vm-platform.nix 2>/dev/null
  || true` (no-op when `/etc/nixos` is not a git checkout; needed when it is,
  since `nixos-rebuild boot --flake /etc/nixos#...` then reads via git+file).
- In the `@persist` copy list add:
  `cp /etc/nixos/vm-platform.nix "${BTRFS_MOUNT}/@persist/etc/nixos/" 2>/dev/null || true`
- The migration summary block precedes the GPU/hypervisor prompts, so no summary
  line is added (matches the existing GPU-variant prompt).

#### 3. `flake.nix`

- Add `statelessVmPlatformModule` next to `featuresModule` /
  `statelessUserOverrideModule`: `[ /etc/nixos/vm-platform.nix ]` when the path
  exists, else `[]`.
- `roles.stateless.hostLocalModules`:
  `statelessUserOverrideModule ++ statelessVmPlatformModule`.

#### 4. `template/etc-nixos-flake.nix`

- Add `vmPlatformFile = ./vm-platform.nix;` + `hasVmPlatform = builtins.pathExists
  vmPlatformFile;` next to `featuresFile`.
- `mkStatelessVariant`: append `++ lib.optional hasVmPlatform vmPlatformFile`.

#### 5. `justfile` / `template/features.nix`

- No change. The dedicated file keeps `features.nix` semantics intact.

### Dependencies

None. No new flake inputs, no external libraries. Context7 not applicable
(internal Nix + shell changes only).

### Configuration changes

- New optional file on stateless VirtualBox hosts: `/etc/nixos/features.nix`
  containing only `vexos.vm.platform = "virtualbox";`.
- No change to `system.stateVersion` in any `configuration-*.nix`.
- No change to CI: `builtins.pathExists /etc/nixos/features.nix` is false in the CI
  sandbox, so `vexos-stateless-*` evaluation is unchanged.

### Risks and mitigations

| Risk | Mitigation |
|------|------------|
| Stateless role does not declare `vexos.features.*`, so reusing `features.nix` breaks eval on hosts that have one. | Avoided — a dedicated `vm-platform.nix` carrying only `vexos.vm.platform` is used instead (see Decision). |
| `vm-platform.nix` not tracked by git → invisible to `git+file://` flake eval. | `stateless-setup.sh` writes it before `git add .`; `migrate-to-stateless.sh` runs `git add vm-platform.nix` explicitly. |
| `vm-platform.nix` not persisted → lost on first stateless reboot (impermanence). | Added to the `/persistent` (setup) and `@persist` (migrate) copy lists; also carried by the wholesale `.git` copy. |
| VirtualBox kernel pin (6.18 LTS) unexpectedly applied. | Only when the user explicitly selects VirtualBox; identical behaviour to the desktop path; rationale already documented in `modules/gpu/vm-guest-additions.nix`. |

### Verifiable success criteria

1. `bash -n scripts/stateless-setup.sh` and `bash -n scripts/migrate-to-stateless.sh` pass.
2. `nix flake show --impure` lists all 30 `nixosConfigurations` unchanged.
3. `sudo nixos-rebuild dry-build --flake .#vexos-stateless-vm` succeeds (no
   `/etc/nixos/features.nix` present → `qemu` default, unchanged from today).
4. With a temporary `/etc/nixos/vm-platform.nix` containing
   `{ vexos.vm.platform = "virtualbox"; }`, `nix eval --impure
   ".#nixosConfigurations.vexos-stateless-vm.config.boot.kernelPackages.kernel.version"`
   resolves to the 6.18 pin (proves the file is now wired in). Remove the temp file.
5. `bash scripts/preflight.sh` exits 0.
