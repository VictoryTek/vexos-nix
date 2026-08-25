# Limine Bootloader Option — Spec

## Current state

- `vexos.bootloader` (`modules/system.nix:35-80`) is a per-host enum, currently
  `"systemd-boot"` (default) or `"grub"` (BIOS/CSM). Each branch is a
  `lib.mkIf` block guarded by an option the same module declares — the
  documented Option-B carve-out, not role-smuggling.
- `modules/boot-discovery.nix` runs a oneshot service on every boot that scans
  every disk's ESP via `sfdisk --dump`, mounts each one, identifies known
  other-OS EFI stubs (Windows, Ubuntu/Fedora/Arch/Debian/Pop!_OS/Manjaro,
  another NixOS), and registers each as a UEFI NVRAM entry via
  `efibootmgr --create`.
- **Confirmed root cause of the reported bug:** NVRAM entries and
  systemd-boot's own menu are disjoint. systemd-boot only auto-discovers
  loaders physically present on the ESP it booted from; it never enumerates
  `Boot####` NVRAM variables. NVRAM entries are only reachable via the
  firmware's own key-press boot menu (F12/Esc/etc.), before any OS
  bootloader loads. The service has been running and succeeding; it was
  never wired to what the user is looking at.
- `scripts/install.sh:529-620` detects BIOS vs UEFI and, for BIOS, patches
  `/etc/nixos/flake.nix`'s `bootloaderModule` block via an `awk` brace-depth
  replace to set `vexos.bootloader = "grub"` / `vexos.grub.device`. For UEFI
  it does nothing — the template's default `bootloaderModule`
  (`template/etc-nixos-flake.nix:103-108`) hardcodes
  `boot.loader.systemd-boot.enable = true;` directly, bypassing
  `vexos.bootloader` (harmless — same value as the module's own default).
- `justfile:116` (`switch` recipe) handles role/variant/DE selection and
  calls `nixos-rebuild switch|boot` against whatever `bootloaderModule` is
  already on disk. It has no bootloader-selection logic today.

## Problem definition

1. Cross-disk dual-boot OS entries are invisible from inside systemd-boot's
   menu — structurally, not as a bug that can be patched in
   `boot-discovery.nix` as currently designed.
2. The user wants Limine available as an **opt-in, per-host** alternative
   (installer + already-installed hosts), with **no host's behavior
   changing until they explicitly choose it** — this repo manages 30
   deployed configs, so the change must be purely additive.
3. If/when a host does move to Limine, the migration needs an actual
   cross-disk boot menu that works, and a controlled cleanup of the
   leftover systemd-boot NVRAM entry + ESP files (confirmed not to happen
   automatically per nixpkgs' `limine-install.py`, which neither detects
   nor removes a prior bootloader).

## Confirmed facts about Limine relevant to safety

- `boot.loader.limine.enable = true` does **not** imply
  `boot.loader.systemd-boot.enable = false` (only GRUB is
  auto-disabled by the upstream module) — must be set explicitly.
- `limine-install.py` creates/updates its own `"Limine"` NVRAM entry; it
  never touches or removes a pre-existing systemd-boot NVRAM entry or ESP
  files (`/boot/EFI/systemd/`, `/boot/loader/entries/`). It does not set
  `BootNext`, and does not guarantee first position in `BootOrder`.
- Limine has no `os-prober` equivalent by design. Cross-disk entries must
  be written into `limine.conf` manually, using
  `guid(<partition-guid>):/EFI/...` path resource syntax, which the docs
  describe as addressing a "unified namespace" not limited to the boot
  disk. **This exact cross-disk case is not proven by a working example
  found in research — only by the doc's general resource-path grammar.**
  Treat as best-effort, not guaranteed, until verified on real/VM hardware.
- `limine.conf` has no documented `!include` directive, so a runtime
  service cannot bolt on a second file — it must edit `/boot/limine.conf`
  directly, in a clearly delimited, idempotent block.
- Editing `/boot/limine.conf` at runtime is safe by default:
  `boot.loader.limine.validateChecksums` defaults `true` but
  `panicOnChecksumMismatch` defaults `false`, and `enrollConfig` defaults
  to the value of `panicOnChecksumMismatch` (`false`). As long as this repo
  does not explicitly turn either on, a runtime-modified config will not
  fail to boot over a checksum mismatch. This must not be overridden.

## Proposed design (additive only — no default changes)

### 1. `modules/system.nix` — new `vexos.bootloader` value

Extend the enum to `[ "systemd-boot" "grub" "limine" ]`, default stays
`"systemd-boot"`. New branch, same Option-B carve-out pattern as the
existing two:

```nix
(lib.mkIf (config.vexos.bootloader == "limine") {
  boot.loader.systemd-boot.enable = false;
  boot.loader.limine = {
    enable         = true;
    efiSupport     = true;
    maxGenerations = 5;
    # enrollConfig/panicOnChecksumMismatch left at their defaults (false) —
    # modules/boot-discovery.nix edits /boot/limine.conf at runtime to add
    # cross-disk entries; enabling either would make that edit fatal at
    # next boot.
  };
  boot.loader.efi.canTouchEfiVariables = true;
})
```

### 2. `modules/boot-discovery.nix` — add a Limine output path

Keep the existing `efibootmgr` NVRAM registration unconditionally (still
useful for the firmware's own F12 menu, regardless of OS bootloader).
Add a second, additive step gated on `config.vexos.bootloader == "limine"`:
after identifying each other-OS ESP and its `partuuid` (already extracted),
render `guid(<partuuid>):/EFI/...` entries and rewrite a clearly delimited
block in `/boot/limine.conf`:

```
#-- BEGIN vexos-boot-discovery (auto-generated, do not edit) --
/Windows Boot Manager [<tag>]
    protocol: efi
    path: guid(<partuuid>):/EFI/Microsoft/Boot/bootmgfw.efi
...
#-- END vexos-boot-discovery --
```

Idempotent by replacing between the markers each run (same pattern as the
existing `register()` idempotency check, just file-based instead of
NVRAM-label-based). No-op when `vexos.bootloader != "limine"`.

### 3. `template/etc-nixos-flake.nix` — document the option

Add a Limine paragraph next to the existing GRUB header-comment block,
following the same `vexos.bootloader = "limine";` pattern already used for
GRUB (not a raw `boot.loader.limine.enable` stanza — `modules/system.nix`
owns the actual assignments, per the existing GRUB comment's own stated
rationale).

### 4. `scripts/install.sh` — installer choice (UEFI path only)

In the existing UEFI branch (currently a no-op besides the `/boot` mount
check), add an opt-in prompt: "Bootloader: systemd-boot (default) or
Limine (newer, opt-in)". If Limine is chosen, patch `bootloaderModule` in
`/etc/nixos/flake.nix` using the same `awk` brace-depth block-replace
already used for the GRUB path, writing `vexos.bootloader = "limine";`.
Default (no input / Enter) stays systemd-boot — zero behavior change for
anyone who doesn't actively choose it.

### 5. `justfile` — two-step migration recipe for already-installed hosts

A single-shot destructive migration is not safe to ship untested — this
repo can't run `nixos-rebuild`/`efibootmgr` in this dev environment (no
Nix, Windows host) to verify the shell logic end to end, and a bad cleanup
step can brick a dual-boot machine. Split into two recipes:

- **`just switch-bootloader limine`** — non-destructive:
  1. Refuses if not UEFI or already on Limine.
  2. Records the current systemd-boot NVRAM entry number(s) before
     touching anything.
  3. Patches `/etc/nixos/flake.nix` (same awk pattern as install.sh) to
     `vexos.bootloader = "limine"`.
  4. `nixos-rebuild switch` (Limine installs alongside the still-present
     systemd-boot entry — nothing removed yet).
  5. Verifies a Limine NVRAM entry now exists; aborts with a clear error
     (config already applied, but no forced reboot) if not.
  6. Reorders `BootOrder` to put Limine first, but leaves the old
     systemd-boot entry and ESP files in place as a fallback.
  7. Tells the user to reboot and confirm Limine actually boots
     successfully before running cleanup.

- **`just switch-bootloader-cleanup`** — destructive, separate invocation:
  1. Hard-gates on proof the current boot session actually used the
     Limine NVRAM entry (`efibootmgr`'s `BootCurrent` must equal Limine's
     boot number) — refuses otherwise, so it can't run right after step 4
     before a reboot has actually happened.
  2. Removes the old systemd-boot NVRAM entry(ies) recorded earlier.
  3. Removes orphaned `/boot/EFI/systemd/` and `/boot/loader/` files.
  4. Reports what was removed.

This keeps the risky, irreversible half of the migration behind an
explicit second command the user only runs after they've personally
confirmed the new bootloader works — matching the project's own
instruction to prefer reversible steps and confirm before destructive
action.

## Risks and mitigations

- **`guid()` cross-disk addressing unverified** → ship it, but call it out
  to the user as best-effort; the two-step justfile design means a failure
  here just leaves the machine on the still-present systemd-boot fallback,
  not bricked.
- **Cannot dry-run `nixos-rebuild`/`efibootmgr` shell logic in this dev
  environment** → implementation will be reviewed line-by-line against
  documented `efibootmgr`/Limine behavior instead of executed; user should
  test `switch-bootloader` on one non-critical machine first.
- **Fleet-wide blast radius** → every change is additive and gated behind
  either an explicit installer choice or an explicit `just
  switch-bootloader` invocation; no existing host's `vexos.bootloader`
  value changes.
- **Windows dev environment** → `nix flake show --impure` and
  `nixos-rebuild dry-build` cannot run here (no Nix installed). Phase 3/6
  build validation will be limited to careful manual Nix syntax/option
  review; actual dry-build validation must happen on the user's NixOS host
  or CI before this is trusted.

## Dependencies

None new — `boot.loader.limine` is already present in the pinned
`nixpkgs` (via `vexos-nix/nixpkgs` follows). No new flake input required.
