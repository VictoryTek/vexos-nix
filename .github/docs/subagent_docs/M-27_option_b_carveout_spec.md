# M-27 — Option B "no lib.mkIf in shared modules" rule needs a carve-out

Status: Phase 1 (Research & Specification)
Source: MASTER_PLAN M-27 (ARCH 2.2) · `modules/system.nix:63,73,148,161`,
`modules/network.nix:108`, `modules/flatpak.nix:51` (all read in full)

## Current State

CLAUDE.md's Module Architecture Pattern section states a blanket rule: "Existing
`lib.mkIf` guards in shared modules are tech debt to be eliminated. Do not add new
ones." The actual intent (per the surrounding rules) is narrower: "Universal base
file... NO `lib.mkIf` guards inside that gate content by role, display flag, or
gaming flag."

Checked every cited instance directly:
- `system.nix:63,73` — gate on `config.vexos.bootloader == "systemd-boot"/"grub"` (a
  bootloader-choice option).
- `system.nix:149,162` — gate on `config.vexos.swap.enable` /
  `config.vexos.btrfs.enable` (auto-detected/overridable per-host toggles, already
  established via H-14's own investigation of the btrfs option).
- `network.nix:108` — gates on `config.vexos.network.staticWired != null` (a
  per-host static-IP config option).
- `flatpak.nix:55` — gates on `config.vexos.flatpak.enable` (a subsystem master
  toggle, `default = true`, explicitly documented as overridable "on VMs or
  resource-constrained hosts").

None of these gate by role, display flag, or gaming flag — each gates a module's own
config block by an option *that same module declares*. This is the standard,
unavoidable NixOS pattern for a toggleable subsystem (there's no way to conditionally
apply `config` based on an option's value without `lib.mkIf`/`lib.mkMerge`), not the
role-smuggling anti-pattern the rule exists to prevent.

## Problem Definition

The blanket rule text is overly broad and doesn't match its own stated intent, which
already correctly names the real anti-pattern (role/display/gaming-flag branching).
Ripping out these 5 `lib.mkIf` guards would require removing the bootloader choice,
swap toggle, btrfs auto-detection, static-IP config, and flatpak master switch
entirely — deleting real, working, requested functionality, not fixing tech debt.

## Proposed Solution

Update CLAUDE.md's Module Architecture Pattern rule text to explicitly carve out
same-module option-gating, matching the MASTER_PLAN's own suggested fix
("document the legitimate server-module enable-flag pattern as an explicit carve-out").
No source module changes — the code in `system.nix`/`network.nix`/`flatpak.nix` is
already correct as-is.

## Implementation Steps

1. `CLAUDE.md` — replace the blanket "existing lib.mkIf... tech debt" line with
   wording that distinguishes the two cases.

## Configuration Changes

None.

## Risks and Mitigations

- **None** — this is a documentation-only change; no `.nix` file is touched.
