# L-15 — `distroName` priority arithmetic re-derived at every site

Status: Phase 1 (Research & Specification)
Source: MASTER_PLAN L-15 (ARCH 3.4) · `configuration-server.nix`,
`configuration-htpc.nix`, `configuration-headless-server.nix`

## Current State

Traced the full priority chain for `system.nixos.distroName` across every
consumption path, not just the three cited files:

1. `modules/branding.nix:92-97` — sets a role-based default via
   `lib.mkDefault (if role == "stateless" then "VexOS Stateless" else if
   role == "server" then "VexOS Server" else if role == "htpc" then
   "VexOS HTPC" else "VexOS Desktop")` (priority 1000). **Missing a branch
   for `"headless-server"`** — falls through to the `"VexOS Desktop"` else
   case for that role, even though `vexos.branding.role`'s own type already
   includes `"headless-server"` as a valid enum value (used correctly by
   this same file's `assetRole` mapping, just not by the `distroName`
   conditional).
2. `configuration-server.nix` / `configuration-htpc.nix` /
   `configuration-headless-server.nix` each set
   `system.nixos.distroName = lib.mkOverride 500 "VexOS <Role>";`
   (priority 500) — for server/htpc this is a byte-for-byte redundant
   re-assertion of what branding.nix's own conditional already produces at
   priority 1000; for headless-server it's the only thing making the value
   correct at all, papering over the missing branch above.
3. Every one of the 24 `hosts/*.nix` files sets its own **bare**
   `system.nixos.distroName = "VexOS <Role> <GPU>";` (priority 100, the
   strongest of the three) — e.g. `hosts/server-amd.nix`'s
   `"VexOS Server AMD"`.

**Critical distinction found while researching this**: `hosts/*.nix` files
are only used by `mkHost` (this repo's own `nixosConfigurations`, e.g.
`vexos-server-amd`) — they are *not* part of `nixosModules.serverBase` /
`htpcBase` / `headlessServerBase`, which is what the thin `/etc/nixos/flake.nix`
wrapper template (the actual end-user deployment path) consumes instead.
Confirmed this concretely by building each `*Base` module standalone via
`lib.nixosSystem` before making any change:
- `nixosModules.serverBase` → `"VexOS Server"`
- `nixosModules.htpcBase` → `"VexOS HTPC"`
- `nixosModules.headlessServerBase` → `"VexOS Headless Server"`

So while the `mkOverride 500` lines never actually win for this repo's own
`mkHost`-generated `nixosConfigurations` (the per-host bare assignment
always wins), they **are** the value that actually reaches real deployed
hosts running the thin-wrapper flake. Deleting them outright (as a naive
reading of "remove the mkOverride 500 workarounds" might suggest) would
silently break `distroName` for every `nixosModules.serverBase`/`htpcBase`
consumer and would leave `headlessServerBase` wrong (no branch in
branding.nix covers it).

## Problem Definition

The `mkOverride 500` lines in the three `configuration-*.nix` files exist
only because `modules/branding.nix`'s own role-conditional is incomplete
(missing `headless-server`) and, for the other two roles, redundantly
re-derives a value the same conditional already produces — duplicated
logic spread across 4 files instead of being correct in the one module
that owns the option.

## Proposed Solution

Complete `modules/branding.nix`'s conditional with the missing
`"headless-server"` branch (`"VexOS Headless Server"`, matching the exact
string the workaround currently produces). With the conditional now
complete and correct for all four non-desktop roles, the three
`mkOverride 500` lines in `configuration-server.nix`/`htpc.nix`/
`headless-server.nix` become true, verifiable no-ops (same resulting
string, now produced by `mkDefault` alone) and can be safely deleted —
this is the single-source-of-truth fix, achieved by completing the
existing option's own logic rather than introducing a brand-new
`vexos.branding.distroName` option layered on top of it (the plan's
literal suggestion), since `branding.nix` already owns exactly this
concern and just needed its role mapping finished.

## Implementation Steps

1. `modules/branding.nix` — add
   `else if config.vexos.branding.role == "headless-server" then "VexOS Headless Server"`
   to the `distroName` conditional.
2. `configuration-server.nix` — remove the `mkOverride 500` line (keep
   `vexos.branding.role = "server"`).
3. `configuration-htpc.nix` — remove the `mkOverride 500` line (keep
   `vexos.branding.role = "htpc"`).
4. `configuration-headless-server.nix` — remove the `mkOverride 500` line
   (keep `vexos.branding.role = "headless-server"`).

## Configuration Changes

None visible — every `nixosConfigurations` output already has a
stronger, host-file bare override that wins regardless; this only changes
what `nixosModules.serverBase`/`htpcBase`/`headlessServerBase` resolve to
in isolation, and it resolves to the *same* strings as before (verified in
Phase 3), not new ones.

## Risks and Mitigations

- **Risk:** removing the `mkOverride 500` lines could silently change
  `distroName` for real deployed hosts using the thin-wrapper flake
  (`nixosModules.*Base`), since that path has no per-host bare override to
  fall back on.
  **Mitigation:** captured each `*Base` module's exact current
  `distroName` value *before* changing anything (`"VexOS Server"`,
  `"VexOS HTPC"`, `"VexOS Headless Server"`), and re-verified all three
  resolve to the identical strings after the fix.
- **Risk:** the 24 in-repo `nixosConfigurations` outputs could be
  affected if a host file's bare assignment were somehow weaker than
  expected.
  **Mitigation:** bare assignment is priority 100, stronger than any
  `mkDefault`/`mkOverride 500` — confirmed via `.drv` hash comparison
  that every affected `nixosConfigurations` output is byte-identical
  before/after.
