# M-13 — All server host variants share the same placeholder ZFS hostId

Status: Phase 1 (Research & Specification)
Source: MASTER_PLAN M-13 (BUGS M15) · `hosts/server-*.nix`, `hosts/headless-server-*.nix`,
`modules/zfs-server.nix` (all read in full)

## Current State

Each of the 8 tracked host files (`hosts/{server,headless-server}-{amd,nvidia,intel,vm}.nix`)
hardcodes a distinct-looking but **committed, shared-across-every-user** placeholder:
`networking.hostId = "a0000001";` (server-amd), `"a0000002"` (server-nvidia), ...
`"b0000004"` (headless-server-vm) — as a **plain (priority-100)** assignment, each with
an existing `# REQUIRED: replace with the real value from the target host` comment.

`modules/zfs-server.nix` already has the right shape of protection:
`networking.hostId = lib.mkDefault "00000000";` plus an assertion
`config.networking.hostId != "00000000"`. But since the host files' plain assignments
(priority 100) beat `zfs-server.nix`'s `mkDefault` (priority 1000), and the assertion
only checks against the literal `"00000000"`, every one of the 8 committed
placeholders (`"a0000001"` through `"b0000004"`) **satisfies** the existing assertion
without being unique at all — the safety net doesn't catch the actual bug.

This matters for real deployments: `justfile:_resolve-flake-dir` documents and supports
building `nixosConfigurations.vexos-server-amd` directly from a plain repo checkout
(not just through the thin `/etc/nixos` wrapper) as a legitimate deployment path. Two
different real machines both doing `just switch server amd` from their own checkouts of
this same repo, without editing the hostId line, would both get `hostId = "a0000001"` —
identical, non-unique — silently defeating ZFS's protection against importing a pool
that's already imported elsewhere (e.g., a drive moved between machines, or a
mistakenly-shared SAN LUN).

Separately verified: `template/etc-nixos-flake.nix` (the thin-wrapper path real
production installs use) already handles this correctly — `networking.hostId =
"XXXXXXXX";` with `scripts/install.sh` substituting a real value derived from
`/etc/machine-id` at install time. That path needs no change.

## Problem Definition

Make the tracked repo's own `hosts/*.nix` placeholders overridable (not a hard
priority-100 commitment) and make the existing assertion actually catch all 8 known
committed placeholder values, not just `"00000000"`.

## Proposed Solution

1. Wrap each host file's hostId assignment in `lib.mkDefault`, matching
   `zfs-server.nix`'s own priority scheme, so a user can override it in that same file
   (or a higher-priority module) without fighting a plain-priority commitment.
2. Extend `zfs-server.nix`'s assertion to reject the full known set of 8 committed
   placeholders (a small, fixed, enumerable list — not the "50+ services must stay in
   sync" scale problem flagged elsewhere in this MASTER_PLAN), so leaving any of them
   unedited fails the build with a clear message, instead of silently succeeding.

## Implementation Steps

1. `hosts/server-amd.nix`, `server-nvidia.nix`, `server-intel.nix`, `server-vm.nix`,
   `headless-server-amd.nix`, `headless-server-nvidia.nix`, `headless-server-intel.nix`,
   `headless-server-vm.nix` — wrap `networking.hostId = "<value>";` with `lib.mkDefault`.
2. `modules/zfs-server.nix` — extend the assertion's rejected-value list from just
   `"00000000"` to all 8 committed placeholders plus `"00000000"`.

## Configuration Changes

None — `template/etc-nixos-flake.nix` already correct, not touched.

## Risks and Mitigations

- **`lib.mkDefault` on the host files doesn't itself fix anything alone** — it only
  matters combined with the assertion actually rejecting the placeholder value; both
  changes are needed together, which is what's implemented.
- **Verify `mkHost`'s real-deployment behavior for a *correctly configured* host is
  unaffected** — confirmed via a synthetic build overriding hostId to a real-looking
  value and checking the assertion passes.
