# VM guest platform split — QEMU/Proxmox vs VirtualBox — Specification

## 1. Current state analysis

Every `*-vm` variant is built as a **union** of QEMU/KVM *and* VirtualBox guest
support. Three files are involved:

| File | Content |
|---|---|
| `modules/gpu/vm.nix` | qemuGuest, spice-vdagentd, VirtualBox guest additions, virtio/qxl modules, governor, btrfs/swap/ZFS overrides, render-node warning |
| `modules/gpu/vanilla-vm.nix` | the same, minus the `vexos.*` options the vanilla role does not declare |
| `modules/gpu/vm-guest-additions.nix` | VirtualBox Guest Additions build fix (overlay) **and** `boot.kernelPackages = lib.mkForce pkgs.linuxPackages_6_18` |

Imported by the 6 `hosts/*-vm.nix` files (one per role).

### The coupling

`virtualisation.virtualbox.guest.enable = true` is set unconditionally, which
forces `virtualboxGuestAdditions` to be **built** on every VM variant —
including pure QEMU/Proxmox guests that can never use it. As
`vm-guest-additions.nix` documents at length, that package does not build
against any kernel in our pin (its `vboxvideo` module calls the removed
`drm_fb_helper_alloc_info()`), which is why the file carries both an
`overrideAttrs` patch and a kernel pin.

The kernel pin is the expensive half:

```nix
boot.kernelPackages = lib.mkForce pkgs.linuxPackages_6_18;   # line 73
```

`lib.mkForce` (priority 50) deliberately outranks every other definition in the
repo, so **all six** VM variants run 6.18 regardless of their role's own kernel
track. For `desktop-vm` and `stateless-vm` that silently replaces
`linuxPackages_latest` (7.x, from `modules/system-latest-kernel.nix`) with a
kernel two LTS releases older — purely to keep a VirtualBox package building
that a Proxmox guest will never load.

### Why this matters beyond tidiness

The same file records that a comparison VM on **kernel 7.1.9 worked** with
Hyprland on the Proxmox display setting where 6.12 failed; 6.18 was chosen as
an untested midpoint. The user reports Omarchy and CachyOS Hyprland — both
shipping current 7.x kernels — boot correctly in this same Proxmox
environment, while `vexos-desktop-vm` never has. Decoupling the kernel pin from
QEMU guests is therefore both a performance fix and the leading candidate
explanation for that failure.

## 2. Problem definition

Support both hypervisor families properly instead of averaging them:

1. **QEMU/KVM/Proxmox guests** (the user's primary environment) must get their
   role's normal kernel and must not build or load VirtualBox guest additions.
2. **VirtualBox guests** must keep working exactly as they do today — guest
   additions, shared folders, clipboard, drag & drop, and the 6.18 pin that
   makes them build.
3. The installer should ask which hypervisor when the VM variant is selected.

## 3. Proposed solution architecture

### 3.1 A `vexos.vm.platform` option, not new flake variants

Add `vexos.vm.platform`, an enum of `"qemu"` (default) and `"virtualbox"`, and
gate the platform-specific blocks on it.

**Rejected alternative — separate `-vbox` flake outputs.** That would take the
flake from 30 `nixosConfigurations` to 36 (one new variant per role). CLAUDE.md
names parallel evaluation of all outputs as the binding resource constraint on
this project, and CI already runs 6 evaluation groups. Six more outputs to
express a two-setting difference is a poor trade.

Option-gating is also the repo's established shape for a toggleable subsystem —
`vexos.btrfs.enable`, `vexos.swap.enable`, `vexos.bootloader`,
`vexos.flatpak.enable`, `vexos.network.staticWired` — and is explicitly the
carve-out in CLAUDE.md's Module Architecture Pattern: `lib.mkIf` guarding a
config block by an option **the same module declares** is the standard,
unavoidable NixOS pattern, not role-smuggling. The `mkIf` guards introduced
here are exactly that shape.

Note that a conditional `imports` list is not available as an alternative —
imports are resolved before option values exist — so `mkIf` is required
regardless of how the code is split across files. Splitting into
`vm-qemu.nix` / `vm-virtualbox.nix` would therefore buy nothing over two
clearly-labelled gated blocks, and would add two files. Kept in place.

### 3.2 Where the option lives

Declared in `modules/gpu/vm-guest-additions.nix`. That is the one file both
`vm.nix` and `vanilla-vm.nix` already import, so it is the only place the
option can be declared once and be visible to both. Its header comment is
updated to reflect that it now owns VM platform selection.

### 3.3 What moves where

| Setting | Today | After |
|---|---|---|
| `services.qemuGuest.enable` | `vm.nix`, `vanilla-vm.nix`, unconditional | same files, gated `platform == "qemu"` |
| `services.spice-vdagentd.enable` | same | same files, gated `platform == "qemu"` |
| `virtualisation.virtualbox.guest.*` (3 options) | `vm.nix` **and** `vanilla-vm.nix`, duplicated | moved into `vm-guest-additions.nix`, gated `platform == "virtualbox"` — removes the duplication |
| `nixpkgs.overlays` guest-additions patch | `vm-guest-additions.nix`, unconditional | gated `platform == "virtualbox"` |
| `boot.kernelPackages = mkForce linuxPackages_6_18` | `vm-guest-additions.nix`, unconditional | gated `platform == "virtualbox"` |
| virtio/qxl `boot.*kernelModules`, governor, btrfs/swap/ZFS overrides, render-node check | `vm.nix` | unchanged — genuinely common to both |

Moving `virtualisation.virtualbox.guest.*` out of `vm.nix`/`vanilla-vm.nix` is
not opportunistic refactoring: those lines *are* the VirtualBox-specific
content this change exists to gate, and they are currently duplicated across
the two files.

`virtio_gpu` / `virtio_blk` / `qxl` stay unconditional. They are cheap, and
`virtio_blk` in particular is load-bearing for initrd boot on QEMU while being
inert on VirtualBox.

### 3.4 Resulting kernel per variant on `platform = "qemu"`

With the `mkForce` gone, each role's own definition wins again:

| Variant | Kernel after change | Source |
|---|---|---|
| `desktop-vm`, `stateless-vm` | `linuxPackages_latest` (7.x) | `modules/system-latest-kernel.nix` |
| `htpc-vm` | `linuxPackages_6_12` | `modules/system-lts-kernel.nix` |
| `server-vm`, `headless-server-vm` | `pkgs.linuxPackages` | `modules/zfs-server.nix:40` (`mkOverride 75`, outranks the LTS module) |
| `vanilla-vm` | nixpkgs default | vanilla sets no `boot.kernelPackages` |

`platform = "virtualbox"` keeps `linuxPackages_6_18` on all six, unchanged from
today.

The `server-vm` / `headless-server-vm` result is a deliberate consequence, not
an oversight: `modules/zfs-server.nix` already claims `boot.kernelPackages` at
priority 75 for ZFS ABI reasons, and its claim was previously being masked by
the `mkForce`. VM guests disable ZFS (`vm.nix` sets
`boot.supportedFilesystems.zfs = lib.mkForce false`), so this is a kernel
change for those two variants with no functional dependency behind it. Called
out in §7 rather than worked around.

### 3.5 Installer prompt

`scripts/install.sh` asks for the hypervisor immediately after the GPU variant
prompt, when and only when `VARIANT = "vm"`, using the existing
`ui_choose` / `center_block` dual-path pattern (gum when available, plain
`read` otherwise) that every other prompt in the script follows.

The result is written to `/etc/nixos/features.nix` alongside
`vexos.desktop.environment`. The current writer (`install.sh:731-748`) is a
three-branch create/replace/append block hardcoded to one key; a second key
would mean copy-pasting it. It is extracted into a `features_set <key>
<value>` shell function and both call sites use it. This is a refactor caused
directly by the change — a second consumer now exists — not adjacent cleanup.

Default remains `"qemu"`, so an existing host that never touches
`features.nix` silently moves from 6.18 to its role kernel on next rebuild.
That is the intended behaviour and is the point of the change; it is recorded
in §7 as a migration note.

## 4. Implementation steps

### Step 1 — `modules/gpu/vm-guest-additions.nix`

Declare `options.vexos.vm.platform` (enum `qemu` | `virtualbox`, default
`qemu`). Wrap the overlay, the three `virtualisation.virtualbox.guest.*`
options (moved in from `vm.nix`/`vanilla-vm.nix`), and the `boot.kernelPackages`
pin in a single `config = lib.mkIf (cfg == "virtualbox")`. Update the header
comment. Preserve every existing explanatory comment — they encode
hard-won upstream detail.

*Verify:* `nix eval` on `…vexos-desktop-vm.config.boot.kernelPackages.kernel.version`
returns a 7.x version; with `vexos.vm.platform = "virtualbox"` overridden it
returns 6.18.

### Step 2 — `modules/gpu/vm.nix`

Remove the three `virtualisation.virtualbox.guest.*` lines and their comment
block (now in Step 1's file). Gate `services.qemuGuest.enable` and
`services.spice-vdagentd.enable` on `platform == "qemu"`.

*Verify:* `nix eval` on `…vexos-desktop-vm.config.virtualisation.virtualbox.guest.enable` → `false`.

### Step 3 — `modules/gpu/vanilla-vm.nix`

Identical treatment to Step 2.

*Verify:* `nix eval` on `…vexos-vanilla-vm.config.services.qemuGuest.enable` → `true`.

### Step 4 — `template/features.nix`

Document `vexos.vm.platform` in the header comment block and add the commented
`# vexos.vm.platform = "qemu";` line, matching the existing style.

### Step 5 — `scripts/install.sh`

Add the hypervisor prompt after the GPU variant block; extract `features_set`;
route both `vexos.desktop.environment` and `vexos.vm.platform` through it.

*Verify:* `bash -n scripts/install.sh` parses clean.

### Step 6 — Validation

`nix flake show --impure` must still list exactly 30 `nixosConfigurations`.
Per-variant `nix eval --impure` on the `.drvPath` of `vexos-desktop-vm`,
`vexos-server-vm` and `vexos-vanilla-vm` forces full evaluation of the three
distinct shapes (full role / ZFS role / vanilla role).

**Environment limitation, stated up front:** the primary working directory is
Windows and has no `nix`. WSL Ubuntu on this machine has Nix 2.34.1, which can
run `nix flake show` and `nix eval`. It **cannot** run
`sudo nixos-rebuild dry-build` — that requires a NixOS host, plus
`/etc/nixos/hardware-configuration.nix`. `scripts/preflight.sh` invokes
`nixos-rebuild`, so Phase 6 cannot complete on this machine and must be run by
the user on a NixOS host. This will be reported as an incomplete gate, not
presented as passing.

## 5. Dependencies

None. No new packages, no new flake inputs, no `follows` declarations needed.
Everything used (`lib.mkOption`, `lib.types.enum`, `lib.mkIf`,
`pkgs.linuxPackages_6_18`) is already in the pin. Context7 is not applicable —
no external library APIs are involved.

## 6. Configuration changes

New option `vexos.vm.platform`, settable in `/etc/nixos/features.nix`:

```nix
vexos.vm.platform = "virtualbox";   # default: "qemu"
```

`system.stateVersion` is untouched in every `configuration-*.nix`.
`hardware-configuration.nix` is not added to the repo.

## 7. Risks and mitigations

| Risk | Mitigation |
|---|---|
| **Existing VirtualBox hosts silently lose guest additions on next rebuild**, because the default is `"qemu"`. | The genuine sharp edge of this change. Symptom is loss of shared folders/clipboard/auto-resize, not a boot failure, and the fix is one line in `features.nix`. Documented in `template/features.nix` and in the commit message. Defaulting to `"virtualbox"` instead would preserve those hosts but keep the 6.18 pin on the majority QEMU case, defeating the purpose. |
| `server-vm` / `headless-server-vm` change kernel (6.18 → `pkgs.linuxPackages`) as a side effect of `zfs-server.nix`'s priority-75 claim resurfacing. | §3.4. ZFS is force-disabled on VM guests so nothing depends on the ABI. If undesirable, the targeted fix is a `mkForce` in `zfs-server.nix` gated on ZFS actually being enabled — a separate change. |
| `desktop-vm` moving 6.18 → 7.x regresses something else in the VM. | Isolated in its own commit precisely so it can be reverted independently of the Hyprland work. |
| `mkIf` inside `nixpkgs.overlays` behaves unexpectedly. | `nixpkgs.overlays` is an ordinary list option; `lib.mkIf` on the enclosing `config` attrset is standard. Confirmed by evaluation in Step 6, not by assumption. |
| Installer `features_set` refactor breaks the working DE path. | `bash -n` syntax check plus the fact that both call sites use identical create/replace/append semantics to the code being replaced. |
| Phase 6 preflight cannot run here. | Reported as incomplete rather than passing; the user runs it on a NixOS host. See §4 Step 6. |
