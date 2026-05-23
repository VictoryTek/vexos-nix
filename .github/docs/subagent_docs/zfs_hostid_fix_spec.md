# zfs_hostid_fix_spec.md
# Specification — ZFS hostId placeholder in `template/etc-nixos-flake.nix`

**Date:** 2026-05-23
**Project:** vexos-nix (NixOS Flake)

---

## Executive Summary

**Status: IMPLEMENTATION REQUIRED.**

Users who copy `template/etc-nixos-flake.nix` to `/etc/nixos/flake.nix` and then
build any `server` or `headless-server` variant hit a hard assertion failure because
`modules/zfs-server.nix` sets `networking.hostId = lib.mkDefault "00000000"` and the
template never overrides it. The fix is to add a clearly-marked `hostModule`
let-binding to the template that carries a `"XXXXXXXX"` placeholder and wire it into
the two affected builders.

---

## 1. Current State

### Template structure (`template/etc-nixos-flake.nix`)

The template is a thin `/etc/nixos/flake.nix` wrapper users copy to their machine.
Inside the `let … in` block of `outputs` it defines:

| Symbol | Purpose |
|---|---|
| `bootloaderModule` | EFI / systemd-boot settings |
| `hardwareModule` | Per-machine hardware toggles — currently empty: `{ ... }: { }` |
| `_mkVariantWith` | Shared builder that constructs a `nixpkgs.lib.nixosSystem` |
| `mkVariant` | Desktop role |
| `mkStatelessVariant` | Stateless role |
| `mkHtpcVariant` | HTPC role |
| `mkVanillaVariant` | Vanilla role |
| `mkHeadlessServerVariant` | Headless server — imports `headlessServerBase` (pulls in `zfs-server.nix`) |
| `mkServerVariant` | GUI server — imports `serverBase` (pulls in `zfs-server.nix`) |

Both server builders include a modules list of the form:

```nix
[
  { environment.etc."nixos/vexos-variant".text = "${variant}\n"; }
  bootloaderModule
  hardwareModule
  ./hardware-configuration.nix
  vexos-nix.nixosModules.serverBase        # (or headlessServerBase)
]
++ modules
++ lib.optional hasServices servicesFile;
```

Nothing in this list overrides `networking.hostId`.

### `modules/zfs-server.nix` (upstream — relevant excerpt)

```nix
networking.hostId = lib.mkDefault "00000000";

assertions = [{
  assertion = config.networking.hostId != "00000000";
  message = ''
    ZFS requires a unique networking.hostId per host. Set it in
    hosts/<role>-<gpu>.nix, e.g.:
      networking.hostId = "deadbeef";
    Generate with:  head -c 8 /etc/machine-id
  '';
}];
```

### What the template currently says about hostId

A comment block immediately above the `mkServerVariant` definition reads:

> Before running `just create-zfs-pool`, add to your
> `/etc/nixos/hardware-configuration.nix` (or a local override module):
>
>   `networking.hostId = "deadbeef";  # ← replace: head -c 8 /etc/machine-id`
>
> Fresh installs without any ZFS pools will see a **build warning** until this
> is set — the warning is informational and does not block the build.

**This comment is wrong in two ways:**

1. The failure is an **assertion error that aborts evaluation** — not a warning.
2. It tells users to edit `hardware-configuration.nix`, a machine-generated file
   that may be regenerated at any time. The template itself is the correct place.

---

## 2. Problem

### Assertion failure sequence

1. User copies `template/etc-nixos-flake.nix` to `/etc/nixos/flake.nix`.
2. User runs `sudo nixos-rebuild switch --flake /etc/nixos#vexos-server-amd`
   (or any `server` / `headless-server` variant).
3. Nix evaluates the flake. `serverBase` / `headlessServerBase` pull in
   `modules/zfs-server.nix`.
4. `zfs-server.nix` sets `networking.hostId = lib.mkDefault "00000000"`. Nothing
   in the template overrides this.
5. The assertion `config.networking.hostId != "00000000"` is `false`.
6. NixOS aborts:

```
error: Failed assertions:
- ZFS requires a unique networking.hostId per host. Set it in
  hosts/<role>-<gpu>.nix, e.g.:
    networking.hostId = "deadbeef";
  Generate with:  head -c 8 /etc/machine-id
```

This breaks **all new server installs** (no value is ever provided) and
**all existing server installs that ran `nix flake update`** after the assertion
was introduced into `zfs-server.nix`.

Non-server roles are unaffected — they do not import `zfs-server.nix`.

---

## 3. Proposed Solution

### Approach

Add a new named let-binding `hostModule` to `template/etc-nixos-flake.nix`
alongside the existing `bootloaderModule` and `hardwareModule`. Include
`hostModule` in the modules list of both `mkServerVariant` and
`mkHeadlessServerVariant`.

**Why a new module rather than editing `hardwareModule`?**

- `hardwareModule` is for physical-hardware toggles (ASUS ROG/TUF, etc.).
  `networking.hostId` is a ZFS-specific identity field — a different concern.
- Separation keeps each module's purpose self-documenting.
- Only server roles should include `hostModule`; desktop/HTPC/stateless/vanilla
  never need `networking.hostId`.

### New `hostModule` let-binding

Insert after `hardwareModule`, before `_mkVariantWith`:

```nix
    # ── ZFS host identity (required for server and headless-server roles) ────
    # ZFS bakes this ID into every pool's vdev label at creation time.
    # It must be unique per machine and must not change after pools are created.
    #
    # REQUIRED: replace XXXXXXXX before your first rebuild.
    # Generate with:  head -c 8 /etc/machine-id
    hostModule = { ... }: {
      networking.hostId = "XXXXXXXX"; # REQUIRED: run: head -c 8 /etc/machine-id
    };
```

### Add `hostModule` to both server builders

**`mkServerVariant`** modules list — change from:

```nix
        [
          { environment.etc."nixos/vexos-variant".text = "${variant}\n"; }
          bootloaderModule
          hardwareModule
          ./hardware-configuration.nix
          vexos-nix.nixosModules.serverBase
        ]
```

to:

```nix
        [
          { environment.etc."nixos/vexos-variant".text = "${variant}\n"; }
          bootloaderModule
          hardwareModule
          hostModule
          ./hardware-configuration.nix
          vexos-nix.nixosModules.serverBase
        ]
```

**`mkHeadlessServerVariant`** modules list — same change:

```nix
        [
          { environment.etc."nixos/vexos-variant".text = "${variant}\n"; }
          bootloaderModule
          hardwareModule
          hostModule
          ./hardware-configuration.nix
          vexos-nix.nixosModules.headlessServerBase
        ]
```

### Fix the misleading comment above `mkServerVariant`

**Replace** the existing comment block (before `mkServerVariant =`):

```nix
    # Server role: GUI server stack.
    #
    # ── ZFS hostId — required before creating ZFS pools ─────────────────────
    # ZFS bakes the host's hostId into every pool's vdev label at creation time.
    # If the hostId changes later (e.g. rebuilding from a workstation), ZFS will
    # refuse to import the pool on next boot.
    #
    # Before running `just create-zfs-pool`, add to your
    # /etc/nixos/hardware-configuration.nix (or a local override module):
    #
    #   networking.hostId = "deadbeef";  # ← replace: head -c 8 /etc/machine-id
    #
    # Fresh installs without any ZFS pools will see a build warning until this is
    # set — the warning is informational and does not block the build.
```

**With:**

```nix
    # Server role: GUI server stack.
    #
    # ── ZFS hostId ───────────────────────────────────────────────────────────
    # ZFS bakes the host's hostId into every pool's vdev label at creation time.
    # If the hostId changes after pools are created, ZFS will refuse to import
    # the pool on next boot.
    #
    # networking.hostId is set in `hostModule` above — replace "XXXXXXXX" with
    # the output of:  head -c 8 /etc/machine-id
    #
    # Leaving "XXXXXXXX" in place causes an assertion failure that aborts the
    # build — it is NOT a warning.
```

The comment above `mkHeadlessServerVariant` (`# See the mkServerVariant comment
above for the ZFS hostId requirement.`) is accurate after the server comment is
fixed and can remain unchanged.

---

## 4. Exact Implementation Steps (line-level)

All changes are confined to **`template/etc-nixos-flake.nix`**.

### Step 1 — Insert `hostModule` let-binding

The `hardwareModule` block currently ends with a single line:

```nix
    hardwareModule = { ... }: { };
```

Insert immediately after that line (blank line for separation, then the new block):

```nix
    # ── ZFS host identity (required for server and headless-server roles) ────
    # ZFS bakes this ID into every pool's vdev label at creation time.
    # It must be unique per machine and must not change after pools are created.
    #
    # REQUIRED: replace XXXXXXXX before your first rebuild.
    # Generate with:  head -c 8 /etc/machine-id
    hostModule = { ... }: {
      networking.hostId = "XXXXXXXX"; # REQUIRED: run: head -c 8 /etc/machine-id
    };
```

### Step 2 — Add `hostModule` to `mkHeadlessServerVariant` modules list

Find the literal text in `mkHeadlessServerVariant`:

```nix
          bootloaderModule
          hardwareModule
          ./hardware-configuration.nix
          vexos-nix.nixosModules.headlessServerBase
```

Change to:

```nix
          bootloaderModule
          hardwareModule
          hostModule
          ./hardware-configuration.nix
          vexos-nix.nixosModules.headlessServerBase
```

### Step 3 — Add `hostModule` to `mkServerVariant` modules list

Find the literal text in `mkServerVariant`:

```nix
          bootloaderModule
          hardwareModule
          ./hardware-configuration.nix
          vexos-nix.nixosModules.serverBase
```

Change to:

```nix
          bootloaderModule
          hardwareModule
          hostModule
          ./hardware-configuration.nix
          vexos-nix.nixosModules.serverBase
```

### Step 4 — Replace the misleading comment above `mkServerVariant`

Locate the block that contains both
`# Fresh installs without any ZFS pools will see a build warning` and ends
just before `mkServerVariant = variant: gpuModule:`. Replace as described in
Section 3.

---

## 5. Dependencies

None. No new packages, flake inputs, or modules are required.

---

## 6. Risks and Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| User forgets to replace `XXXXXXXX` | Medium | Placeholder is visually jarring; comment + assertion both force attention. Build aborts with an actionable error. |
| User sets a duplicate hostId across machines | Low | Out of scope for the template; each user must run `head -c 8 /etc/machine-id` per machine. The comment provides the exact command. |
| `hostModule` applied to non-ZFS roles | N/A | Only `mkServerVariant` and `mkHeadlessServerVariant` include `hostModule`. All other builders are unchanged. |

---

## 7. Files Modified

| File | Change |
|---|---|
| `template/etc-nixos-flake.nix` | Add `hostModule` let-binding; add to two builder modules lists; fix misleading comment above `mkServerVariant` |

No other files are modified. `modules/zfs-server.nix`, `hosts/*.nix`, and all
`configuration-*.nix` files are unchanged.
