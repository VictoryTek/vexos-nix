# justfile: server GUI/headless sub-prompt — Spec

## Current State Analysis

`scripts/install.sh` (the canonical UX reference) presents role selection as
5 options — desktop / stateless / htpc / server / vanilla — with no separate
"headless-server" top-level entry (`scripts/install.sh:366-399`). When the
user picks `server`, a dedicated follow-up prompt asks GUI vs Headless
(`scripts/install.sh:401-431`), and only if "headless" is chosen does the
script remap `ROLE` to `headless-server` internally. This mirrors how the
installer treats desktop-environment selection as a role-specific follow-up,
not a top-level menu item.

`justfile`'s `switch` recipe (`justfile:177-200`) and `update` recipe
(`justfile:721-748`) instead list `server` and `headless-server` as two
separate top-level menu choices (4 and 5), with no sub-prompt. A user who
picks "server" always gets the GUI server role directly; there is no way to
reach headless-server from that path except by knowing to pick option 5
up front. This is the exact behavior the user flagged as inconsistent with
the installer they're used to.

## Problem Definition

Make `just switch` (and `just update`'s no-variant fallback path) match the
installer's UX: a single "server" menu entry, followed by a GUI/Headless
sub-prompt that resolves to `ROLE=server` or `ROLE=headless-server`.

## Proposed Solution

In both `switch` and `update` recipes:

1. Collapse the role menu from 6/5 choices down to 5/4 — remove the
   standalone `headless-server` entry, matching install.sh's list order and
   wording (`desktop / stateless / htpc / server / vanilla` for `switch`;
   `switch` also keeps its existing `vanilla` entry which `update`'s menu
   currently lacks — no change to that asymmetry, out of scope).
2. After `ROLE` is resolved (whether from menu selection or already passed
   as `server` via positional arg), if `ROLE = "server"`, show a new
   sub-prompt:
   ```
   Select server type:
     1) Headless Server — CLI only, no desktop environment
     2) GUI Server      — GNOME desktop environment
   ```
   matching `scripts/install.sh:410-425` wording exactly. Accept
   `1|headless` and `2|gui` (default menu numbering matches install.sh: 1 =
   headless, 2 = gui).
3. If the sub-prompt resolves to headless, remap `ROLE="headless-server"`.
   If gui, leave `ROLE="server"`.
4. This sub-prompt only fires when `ROLE` was just resolved to `"server"`
   through the interactive menu — i.e., it lives inside the existing
   `if [ -z "$ROLE" ]; then ... fi` block, right after the role `case`
   statement resolves, not as a standalone always-run block. This preserves
   the direct non-interactive path: `just switch server amd` and
   `just switch headless-server amd` continue to work unchanged, since a
   caller who already knows which of the two they want can keep passing it
   explicitly as the first positional arg. Only the interactive (no-args)
   menu path changes.

## Implementation Steps

Both recipes have effectively duplicated role-menu logic (justfile is one
big bash block per recipe, not a shared function), so the same edit pattern
is applied twice:

- `justfile:177-200` (`switch` role menu) — remove headless-server menu
  entry (item 5), renumber vanilla to 5, add the server sub-prompt
  immediately after the `while` loop closes.
- `justfile:729-748` (`update` role menu, stateless-reboot fallback path) —
  same edit; this menu currently has no vanilla entry, so it goes from 5
  items to 4, with the sub-prompt added the same way.

No changes to `_resolve-flake-dir`, `TARGET` construction, `_features_set`,
or any Nix module — `ROLE` still ends up as either the literal string
`"server"` or `"headless-server"`, exactly as before; only how that value is
reached interactively changes. This is a pure bash-prompt-flow edit confined
to `justfile`, so it fits the "internal code changes with no new
dependencies" carve-out — no Context7 lookup applies.

## Dependencies

None — no new external libraries or nixpkgs packages.

## Configuration Changes

None — `features.nix`, module imports, and `TARGET` naming are unaffected.

## Risks and Mitigations

- **Risk:** Non-interactive callers (scripts, muscle memory) that pass
  `headless-server` as an explicit positional role arg. **Mitigation:** the
  sub-prompt only triggers on the interactive `-z "$ROLE"` path; explicit
  positional args bypass it entirely, so `just switch headless-server amd`
  keeps working.
- **Risk:** `just --list` and default recipe's server hint text
  (`justfile:9,11`) reference `*server*` variant matching against
  `/etc/nixos/vexos-variant`, which is unaffected since the final `ROLE`
  string values (`server` / `headless-server`) are unchanged.
- **Risk:** Divergence from install.sh wording/order in the future.
  **Mitigation:** sub-prompt copy is taken verbatim from
  `scripts/install.sh:410-413`.

## Build Validation Plan (Phase 3)

This change touches only bash prompt logic in `justfile`, not any `.nix`
file, so no `nixosConfigurations` output, module import, or evaluation
result changes. Standard Phase 3 steps apply:
- `nix flake show --impure`
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd`
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia`
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm`
- Since the change touches the server/headless-server selection path:
  `sudo nixos-rebuild dry-build --flake .#vexos-server-amd`
  `sudo nixos-rebuild dry-build --flake .#vexos-headless-server-amd`
- Manual interactive smoke test of `just switch` (Ctrl+C before confirming
  an actual `nixos-rebuild switch`) to confirm the new prompt flow reaches
  both `ROLE=server` and `ROLE=headless-server` correctly, and that
  `just switch server amd` / `just switch headless-server amd` still bypass
  the sub-prompt.
